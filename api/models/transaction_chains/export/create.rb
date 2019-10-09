module TransactionChains
  class Export::Create < ::TransactionChain
    label 'Create'

    # @param dataset [::Dataset]
    # @param opts [Hash]
    # @option opts [::Snapshot] :snapshot
    # @option opts [Boolean] :all_vps
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @option opts [Boolean] :enabled
    def link_chain(dataset, opts = {})
      if opts[:snapshot]
        sip = find_snap_in_pool(opts[:snapshot])
        dip = sip.dataset_in_pool
        snap_clone = use_chain(SnapshotInPool::UseClone, args: [sip, nil])
      else
        dip = dataset.primary_dataset_in_pool!
      end

      begin
        export = ::Export.create!(
          dataset_in_pool: dip,
          snapshot_in_pool_clone: snap_clone,
          user: dataset.user,
          all_vps: opts[:all_vps] ? true : false,
          path: export_path(dip, sip),
          rw: opts[:rw] ? true : false,
          subtree_check: opts[:subtree_check] ? true : false,
          root_squash: opts[:root_squash] ? true : false,
          sync: opts[:sync] ? true : false,
          enabled: opts[:enabled] ? true : false,
          expiration_date: sip ? Time.now + 3 * 24 * 60 * 60 : nil,
        )
      rescue ActiveRecord::RecordNotUnique
        msg =
          if sip
            "snapshot #{dataset.full_name}@#{sip.snapshot.name} is already "+
            "exported"
          else
            "dataset #{dataset.full_name} is already exported"
          end

        raise VpsAdmin::API::Exceptions::DatasetAlreadyExported, msg
      end

      concerns(:affect, [export.class.name, export.id])
      lock(export)

      netif = ::NetworkInterface.create!(
        export: export,
        kind: 'veth_routed',
        name: 'eth0',
      )
      lock(netif)

      ip_addr = pick_ip_address(export.user, dip.pool.node.location)
      lock(ip_addr)
      ip_addr.update!(network_interface: netif)

      host_addr = ip_addr.host_ip_addresses.first

      append_t(Transactions::Export::Create, args: [export, host_addr]) do |t|
        t.create(export)
        t.just_create(netif)
        t.edit_before(ip_addr, network_interface_id: nil)
      end

      if export.all_vps
        ips = ::IpAddress.joins(:network, network_interface: :vps).where(
          networks: {ip_version: 4},
          vpses: {user_id: export.user_id},
        ).to_a

        hosts = ips.map do |ip|
          ::ExportHost.create!(
            export: export,
            ip_address: ip,
            rw: export.rw,
            sync: export.sync,
            subtree_check: export.subtree_check,
            root_squash: export.root_squash,
          )
        end

        append_t(Transactions::Export::AddHosts, args: [export, hosts]) do |t|
          hosts.each { |host| t.just_create(host) }
        end
      end

      append_t(Transactions::Export::Enable, args: export) if export.enabled
      export
    end

    protected
    # TODO:
    #   - we might want to divide addresses by purpose -- VPS or NFS exports, etc.
    #   - /32 is enough, we shouldn't take larger addresses
    def pick_ip_address(user, location)
      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(
              user,
              location,
              4,
              :private_access,
            )
            lock(ip)
            return ip
          end

        rescue ActiveRecord::RecordNotFound
          fail 'no ipv4_private available'

        rescue ResourceLocked
          sleep(0.25)
          retry
        end
      end
    end

    def find_snap_in_pool(snapshot)
      hv = pr = bc = nil

      snapshot.snapshot_in_pools
        .includes(dataset_in_pool: [:pool])
        .joins(dataset_in_pool: [:pool])
        .all.group('pools.role').each do |sip|
        case sip.dataset_in_pool.pool.role.to_sym
        when :hypervisor
          hv = sip
        when :primary
          pr = sip
        when :backup
          bc = sip
        end
      end

      bc || pr || hv
    end

    def export_path(dip, sip)
      if sip
        File.join(dip.pool.export_root, "#{dip.dataset.full_name}-#{sip.snapshot.name}")
      else
        File.join(dip.pool.export_root, dip.dataset.full_name)
      end
    end
  end
end
