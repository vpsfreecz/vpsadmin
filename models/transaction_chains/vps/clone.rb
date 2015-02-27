module TransactionChains
  # Clone VPS to new or another VPS.
  class Vps::Clone < ::TransactionChain
    label 'Clone VPS'

    def link_chain(vps, node, attrs)
      lock(vps)

      # When cloning to a new VPS:
      # - Create datasets - clone properties
      # - Create vz root
      # - Copy config
      # - Allocate resources (default or the same)
      # - Clone mounts (generate action scripts, snapshot mount references)
      # - Transfer data (one or two runs depending on attrs[stop])
      # - Set features

      # When cloning into another VPS:
      # - Stop target VPS
      # - Destroy all datasets
      # - Reallocate resources if attrs[resources]
      # - Continue the process as above, except creating vz root

      # FIXME: dataset plans

      @src_pool = vps.dataset_in_pool.pool
      @dst_pool = node.pools.where(role: :hypervisor).take!

      src_features = {}
      dst_features = {}

      if attrs[:features]
        vps.vps_features.all.each do |f|
          src_features[f.name.to_sym] = f
        end
      end

      if attrs[:vps] # clone into
        dst_vps = attrs[:vps]

        # Destroy all current datasets
        use_chain(DatasetInPool::Destroy, args: [dst_vps.dataset_in_pool, true])

        # Reallocate resources
        if attrs[:resources]
          vps_resources = dst_vps.reallocate_resources({
              memory: vps.memory,
              swap: vps.swap,
              cpu: vps.cpu
          }, dst_vps.user)
        end

        dst_vps.dataset_in_pool = vps_dataset(vps, dst_vps)
        lock(dst_vps.dataset_in_pool)

      else # clone to a new VPS
        dst_vps = ::Vps.new(
            m_id: attrs[:user].id,
            vps_hostname: attrs[:hostname],
            vps_template: vps.vps_template,
            vps_info: "Cloned from #{vps.id}. Original info:\n#{vps.vps_info}",
            vps_server: node.id,
            vps_onboot: vps.vps_onboot,
            vps_onstartall: vps.vps_onstartall,
            vps_config: attrs[:configs] ? vps.vps_config : '',
            confirmed: ::Vps.confirmed(:confirm_create),
            vps_backup_export: 0, # FIXME: remove this shit
            vps_backup_exclude: '' # FIXME: remove this shit
        )
        dst_vps.dns_resolver = dns_resolver(vps, dst_vps)
        dst_vps.save!
        lock(dst_vps)

        ::VpsFeature::FEATURES.each_key do |name|
          ::VpsFeature.create!(
              vps: dst_vps,
              name: name,
              enabled: attrs[:features] ? src_features[name] : false
          )
        end

        # FIXME: do not fail when there are insufficient resources.
        # It is ok when the available resource is higher than minimum.
        # Perhaps make it a boolean attribute determining if resources
        # must be allocated all or if the available number is sufficient.
        vps_resources = dst_vps.allocate_resources(
            required: %i(cpu memory swap),
            optional: [],
            user: dst_vps.user,
            chain: self,
            values: attrs[:resources] ? {
                cpu: vps.cpu,
                memory: vps.memory,
                swap: vps.swap
            } : {}
        )

        dst_vps.dataset_in_pool = vps_dataset(vps, dst_vps)
        lock(dst_vps.dataset_in_pool)

        append(Transactions::Vps::CreateRoot, args: [dst_vps, node])
        append(Transactions::Vps::CreateConfig, args: [dst_vps]) do
          create(dst_vps)

          dst_features.each_value do |f|
            just_create(f)
          end
        end
      end

      dst_vps.save!

      use_chain(Vps::SetResources, args: [dst_vps, vps_resources]) if vps_resources

      # Configs
      if attrs[:configs]
        use_chain(Vps::ApplyConfig, args: [dst_vps, vps.vps_configs.pluck(:id)])

      else
        use_chain(Vps::ApplyConfig, args: [dst_vps, vps.node.environment.vps_configs.pluck(:id)])
      end

      # Transfer data
      datasets = serialize_datasets(dst_vps.dataset_in_pool)
      datasets.insert(0, [vps.dataset_in_pool, dst_vps.dataset_in_pool])

      # Create all datasets and make initial transfer
      datasets.each do |pair|
        src, dst = pair

        if src != vps.dataset_in_pool
          use = dst.allocate_resource!(
              :diskspace,
              src.diskspace,
              user: dst_vps.user
          )

          properties = ::DatasetProperty.clone_properties!(src, dst)

          append(Transactions::Storage::CreateDataset, args: dst) do
            create(dst)
            create(use)

            properties.each_value do |p|
              create(p)
            end
          end
        end

        use_chain(Dataset::Snapshot, args: src)
        use_chain(Dataset::Transfer, args: [src, dst])
      end

      # Make a second transfer if requested
      if attrs[:stop]
        use_chain(Vps::Stop, args: vps)

        datasets.each do |pair|
          src, dst = pair

          use_chain(Dataset::Snapshot, args: src)
          use_chain(Dataset::Transfer, args: [src, dst])
        end

        use_chain(Vps::Start, args: vps) if vps.running
      end

      # Fix snapshots
      # Dataset::Transfer creates snapshot in pools for vps.dataset_in_pool.dataset,
      # not dst_vps. This is neccessary for how the transfer works and now it must
      # be fixed - create new snapshot objects for dst dataset and move snapshot
      # in pools.
      snapshot_name_fixes = {}
      new_snapshots = []

      datasets.each do |pair|
        _, dst = pair

        dst.snapshot_in_pools.order('snapshot_id').each do |sip|
          s = ::Snapshot.create!(
              dataset: dst.dataset,
              name: sip.snapshot.name,
              confirmed: ::Snapshot.confirmed(:confirm_create),
              created_at: sip.snapshot.created_at
          )

          snapshot_name_fixes[sip.snapshot.id] = [sip.snapshot.name, s.id]
          new_snapshots << s

          sip.update!(snapshot: s)
        end
      end

      # Now fix snapshot names - snapshot name is updated by vpsAdmind
      # to the time when it was actually created.
      append(Transactions::Storage::CloneSnapshotName, args: [dst_vps.dataset_in_pool.pool.node, snapshot_name_fixes]) do
        new_snapshots.each { |s| create(s) }
      end

      # IP addresses
      clone_ip_addresses(vps, dst_vps) unless attrs[:vps]

      # Mounts
      clone_mounts(vps, dst_vps, datasets)

      # Features
      append(Transactions::Vps::Features, args: [dst_vps, dst_features])

      if vps.running
        use_chain(TransactionChains::Vps::Start, args: dst_vps)
      end

      dst_vps
    end

    # Pick correct DNS resolver. If the VPS is being cloned
    # to a different location and its DNS resolver is not universal,
    # it must be changed to DNS resolver in target location.
    def dns_resolver(vps, dst_vps)
      if vps.dns_resolver.dns_is_universal
        vps.dns_resolver

      else
        ::DnsResolver.pick_suitable_resolver_for_vps(dst_vps)
      end
    end

    # Create a new dataset for target VPS.
    def vps_dataset(vps, dst_vps)
      ds = ::Dataset.new(
          name: dst_vps.id.to_s,
          user: dst_vps.user,
          user_editable: false,
          user_create: true,
          user_destroy: false,
          confirmed: ::Dataset.confirmed(:confirm_create)
      )

      # A hash containing all not-inherited properties, which must
      # be set on the cloned dataset as well.
      root_properties = {}

      vps.dataset_in_pool.dataset_properties.each do |p|
        root_properties[p.name.to_sym] = p.value unless p.inherited
      end

      use_chain(Dataset::Create, args: [
          @dst_pool,
          nil,
          [ds],
          false,
          root_properties,
          dst_vps.user,
          "vps#{dst_vps.id}"
      ]).last
    end

    def serialize_datasets(dataset_in_pool)
      ret = []

      dataset_in_pool.dataset.descendants.arrange.each do |k, v|
        ret.concat(recursive_serialize(k, v))
      end

      ret
    end

    def recursive_serialize(dataset, children)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: @src_pool).take

      return ret unless dip

      lock(dip)

      dst = ::DatasetInPool.create!(
          pool: @dst_pool,
          dataset_id: dip.dataset_id
      )

      lock(dst)

      ret << [dip, dst]

      # Then children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool: @src_pool).take
          next unless dip

          lock(dip)

          dst = ::DatasetInPool.create!(
              pool: @dst_pool,
              dataset_id: dip.dataset_id
          )

          lock(dst)

          ret << [dip, dst]

        else
          ret.concat(recursive_serialize(k, v))
        end
      end

      ret
    end

    # Clone IP addresses.
    # Allocates the equal number (or how many are available) of
    # IP addresses.
    def clone_ip_addresses(vps, dst_vps)
      ips = {
          ipv4: vps.ip_addresses.where(ip_v: 4).count,
          ipv6: vps.ip_addresses.where(ip_v: 6).count
      }

      versions = [:ipv4]
      versions << :ipv6 if dst_vps.node.location.has_ipv6

      ip_resources = dst_vps.allocate_resources(
          dst_vps.node.environment,
          required: [],
          optional: versions,
          user: dst_vps.user,
          chain: self,
          values: ips
      )

      if ip_resources.size > 0
        append(Transactions::Utils::NoOp, args: dst_vps.vps_server) do
          ip_resources.each { |r| create(r) }
        end
      end
    end

    # Clone mounts.
    # Snapshot mounts are skipped. Dataset mounts are checked if it is
    # a mount of a subdataset of this particular +vps+. If it is, the cloned
    # dataset is mounted instead.
    def clone_mounts(vps, dst_vps, datasets)
      mounts = []

      vps.mounts.each do |m|
        if m.snapshot_in_pool_id
          # Snapshot mount is NOT cloned - a snapshot can only be mounted
          # once, for now...
          next
        end

        dst_m = ::Mount.new(
            vps: dst_vps,
            dataset_in_pool: nil,
            dst: m.dst,
            mounts_opts: m.mount_opts,
            umounts_opts: m.umount_opts,
            mount_type: m.mount_type,
            user_editable: m.user_editable,
            mode: m.mode,
            confirmed: ::Mount.confirmed(:confirm_create)
        )

        # Check if it is a mount of cloned dataset
        datasets.each do |pair|
          src, dst = pair

          if m.dataset_in_pool_id == src.id
            dst_m.dataset_in_pool = dst
            break
          end
        end

        mounts << dst_m.save!
      end

      use_chain(Vps::Mounts, args: dst_vps)

      if mounts.size > 0
        append(Transactions::Vps::NoOp, args: dst_vps.vps_server) do
          mounts.each { |m| create(m) }
        end
      end
    end
  end
end
