module TransactionChains
  module Vps::CloneBase
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

    def clone_configs(vps, dst_vps, clone_configs)
      if clone_configs
        use_chain(Vps::ApplyConfig, args: [dst_vps, vps.vps_configs.pluck(:id)])

      else
        use_chain(Vps::ApplyConfig, args: [
            dst_vps,
            vps.node.environment.vps_configs.pluck(:id)
        ])
      end
    end

    def clone_hostname(vps, dst_vps, attrs)
      append(Transactions::Vps::Hostname, args: [
          dst_vps,
          vps.hostname,
          attrs[:hostname]
      ])
    end

    def clone_dns_resolver(vps, dst_vps)
      append(Transactions::Vps::DnsResolver, args: [
          dst_vps,
          vps.dns_resolver,
          dst_vps.dns_resolver
      ])
    end
    
    # A hash containing all not-inherited properties, which must
    # be set on the cloned dataset as well.
    def root_dataset_properties(vps)
      root_properties = {}

      vps.dataset_in_pool.dataset_properties.each do |p|
        root_properties[p.name.to_sym] = p.value unless p.inherited
      end

      root_properties
    end
    
    def clone_dataset_plans(src_dip, dst_dip)
      plans = []

      src_dip.dataset_in_pool_plans.includes(
          environment_dataset_plan: [:dataset_plan]
      ).each do |dip_plan|
        plans << dip_plan
      end

      unless plans.empty?
        append(Transactions::Utils::NoOp, args: find_node_id) do
          plans.each do |dip_plan|
            plan = dip_plan.environment_dataset_plan.dataset_plan
            
            # Do not add the plan in the target environment is for admins only
            begin
              next unless ::EnvironmentDatasetPlan.find_by!(
                  dataset_plan: plan,
                  environment: dst_dip.pool.node.environment
              ).user_add

            rescue ActiveRecord::RecordNotFound
              next  # the plan is not present in the target environment
            end

            begin
              VpsAdmin::API::DatasetPlans.plans[plan.name.to_sym].register(
                  dst_dip,
                  confirmation: self
              )

            rescue VpsAdmin::API::Exceptions::DatasetPlanNotInEnvironment
              # This exception should never be raised, as the not-existing plan
              # in the target environment is caught by the rescue above.
              next
            end
          end
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
            dataset_in_pool: m.dataset_in_pool,
            dst: m.dst,
            mount_opts: m.mount_opts,
            umount_opts: m.umount_opts,
            mount_type: m.mount_type,
            user_editable: m.user_editable,
            mode: m.mode,
            confirmed: ::Mount.confirmed(:confirm_create)
        )

        # Check if it is a mount of a cloned dataset.
        datasets.each do |src, dst|
          if m.dataset_in_pool_id == src.id
            dst_m.dataset_in_pool = dst
            break
          end
        end
        # If it is not mount of a cloned dataset, than the +dst_m.dataset_in_pool+
        # may remain the same.

        dst_m.save!
        mounts << dst_m
      end

      use_chain(Vps::Mounts, args: dst_vps)

      if mounts.size > 0
        append(Transactions::Utils::NoOp, args: dst_vps.vps_server) do
          mounts.each { |m| create(m) }
        end
      end
    end

    def transfer_datasets(datasets, urgent: nil)
      @transfer_snapshots ||= []

      datasets.each do |src, dst|
          @transfer_snapshots << use_chain(Dataset::Snapshot, args: src, urgent: urgent)
          use_chain(Dataset::Transfer, args: [src, dst], urgent: urgent)
      end
    end
    
    # Dataset::Transfer creates snapshot in pools for vps.dataset_in_pool.dataset,
    # not dst_vps. This is neccessary for how the transfer works and now it must
    # be fixed - create new snapshot objects for dst dataset and move snapshot
    # in pools.
    def fix_snapshots(dst_vps, datasets)
      @snapshot_name_fixes ||= {}
      new_snapshots = []

      datasets.each do |_, dst|
        dst.snapshot_in_pools.order('snapshot_id').each do |sip|
          s = ::Snapshot.create!(
              dataset: dst.dataset,
              name: sip.snapshot.name,
              confirmed: ::Snapshot.confirmed(:confirm_create),
              created_at: sip.snapshot.created_at
          )

          @snapshot_name_fixes[sip.snapshot.id] = [sip.snapshot.name, s.id]
          new_snapshots << s

          sip.update!(snapshot: s)
        end
      end
      
      snapshot_name_fixes = @snapshot_name_fixes

      # Now fix snapshot names - snapshot name is updated by vpsAdmind
      # to the time when it was actually created.
      append(Transactions::Storage::CloneSnapshotName, args: [
          dst_vps.dataset_in_pool.pool.node,
          snapshot_name_fixes
      ]) do
        new_snapshots.each { |s| create(s) }
      end
    end

    # Remove clone snapshots
    def cleanup_transfer_snapshots
      @transfer_snapshots.each do |src_sip|
        dst_sip = ::SnapshotInPool.joins(:dataset_in_pool).where(
            snapshot_id: @snapshot_name_fixes[ src_sip.snapshot_id ][1],
            dataset_in_pools: {pool_id: @dst_pool.id}
        ).take!

        use_chain(SnapshotInPool::Destroy, args: src_sip)
        use_chain(SnapshotInPool::Destroy, args: dst_sip)
      end
    end
  end
end
