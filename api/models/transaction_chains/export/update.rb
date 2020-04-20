module TransactionChains
  class Export::Update < ::TransactionChain
    label 'Update'
    allow_empty

    # @param export [::Export]
    # @param opts [Hash]
    # @option opts [Boolean] :all_vps
    # @option opts [Boolean] :rw
    # @option opts [Boolean] :sync
    # @option opts [Boolean] :subtree_check
    # @option opts [Boolean] :root_squash
    # @option opts [Integer] :threads
    # @option opts [Boolean] :enabled
    def link_chain(export, opts = {})
      concerns(:affect, [export.class.name, export.id])
      lock(export)

      new_export = ::Export.find(export.id)
      new_export.assign_attributes(opts)

      db_changes = {}
      toggle = nil
      set = false
      add_hosts = []

      new_export.changed.each do |attr|
        case attr
        when 'all_vps', 'rw', 'sync', 'subtree_check', 'root_squash'
          db_changes[attr] = new_export.send(attr)
        when 'threads'
          db_changes[attr] = new_export.send(attr)
          set = true
        when 'enabled'
          toggle = new_export.enabled
        end
      end

      add_hosts = create_missing_hosts(new_export) if new_export.all_vps

      if toggle.nil? && !set && add_hosts.empty?
        new_export.save!
        return new_export
      end

      if toggle === false
        append_t(Transactions::Export::Disable, args: [new_export]) do |t|
          t.edit(export, enabled: new_export.enabled)
        end
      end

      append_t(Transactions::Export::Set, args: [export, new_export]) if set

      if db_changes.any?
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.edit(export, db_changes)
        end
      end

      if add_hosts.any?
        append_t(Transactions::Export::AddHosts, args: [new_export, add_hosts]) do |t|
          add_hosts.each { |host| t.just_create(host) }
        end
      end

      if toggle === true
        append_t(Transactions::Export::Enable, args: [new_export]) do |t|
          t.edit(export, enabled: new_export.enabled)
        end
      end

      export
    end

    protected
    def create_missing_hosts(export)
      ips = ::IpAddress.joins(:network, network_interface: :vps).where(
        networks: {ip_version: 4},
        vpses: {user_id: export.user_id},
      ).to_a

      ips.map do |ip|
        begin
          ::ExportHost.create!(
            export: export,
            ip_address: ip,
            rw: export.rw,
            sync: export.sync,
            subtree_check: export.subtree_check,
            root_squash: export.root_squash,
          )
        rescue ActiveRecord::RecordNotUnique
          nil
        end
      end.compact
    end
  end
end
