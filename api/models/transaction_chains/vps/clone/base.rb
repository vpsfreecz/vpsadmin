module TransactionChains
  module Vps::Clone::Base
    def check_cgroup_version!(vps, dst_node)
      check_v =
        if vps.cgroup_version == 'cgroup_any'
          vps.os_template.cgroup_version
        else
          vps.cgroup_version
        end

      return if check_v == 'cgroup_any'

      if check_v == 'cgroup_v1' && dst_node.cgroup_version != check_v
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "VPS requires cgroup v1 and #{dst_node.domain_name} has cgroup v2"

      elsif check_v == 'cgroup_v2' && dst_node.cgroup_version != check_v
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "VPS requires cgroup v2 and #{dst_node.domain_name} has cgroup v1"
      end
    end

    # Pick correct DNS resolver. If the VPS is being cloned
    # to a different location and its DNS resolver is not universal,
    # it must be changed to DNS resolver in target location.
    def dns_resolver(vps, dst_vps)
      if vps.dns_resolver_id.nil?
        nil

      elsif vps.dns_resolver.is_universal
        vps.dns_resolver

      else
        ::DnsResolver.pick_suitable_resolver_for_vps(dst_vps)
      end
    end

    def clone_hostname(vps, dst_vps, attrs)
      return unless vps.manage_hostname

      append(Transactions::Vps::Hostname, args: [
               dst_vps,
               vps.hostname,
               attrs[:hostname]
             ])
    end

    def clone_dns_resolver(vps, dst_vps)
      return unless vps.dns_resolver

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

      return if plans.empty?

      append(Transactions::Utils::NoOp, args: find_node_id) do
        plans.each do |dip_plan|
          plan = dip_plan.environment_dataset_plan.dataset_plan

          # Do not add the plan in the target environment is for admins only
          begin
            next unless ::EnvironmentDatasetPlan.find_by!(
              dataset_plan: plan,
              environment: dst_dip.pool.node.location.environment
            ).user_add
          rescue ActiveRecord::RecordNotFound
            next # the plan is not present in the target environment
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
          rescue ActiveRecord::RecordNotUnique => e # rubocop:disable Lint/DuplicateBranch
            # The dataset in pool already is in this plan. The only way this could
            # happen is if the code connected to hook DatasetInPool.create registered
            # it.
            # As it is already registered, we may skip it.
            next
          end
        end
      end
    end

    def clone_dataset_expansions(src_dip, dst_dip, dst_vps)
      src_exp = src_dip.dataset.dataset_expansion
      return if src_exp.nil?

      dst_exp = src_exp.dup
      dst_exp.vps = dst_vps
      dst_exp.dataset = dst_dip.dataset

      # Timestamps are not copied by #dup
      dst_exp.created_at = src_exp.created_at
      dst_exp.updated_at = src_exp.updated_at

      dst_exp.save!

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        # Create copied expansion
        t.just_create(dst_exp)

        # Copy expansion history
        src_exp.dataset_expansion_histories.each do |src_hist|
          dst_hist = src_hist.dup
          dst_hist.dataset_expansion = dst_exp
          dst_hist.created_at = src_hist.created_at
          dst_hist.updated_at = src_hist.updated_at
          dst_hist.save!

          t.just_create(dst_hist)
        end

        # Set expansion on dataset
        t.edit(dst_dip.dataset, dataset_expansion_id: dst_exp.id)
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
          confirmed: ::Mount.confirmed(:confirm_create),
          expiration_date: m.expiration_date,
          enabled: m.enabled,
          master_enabled: m.master_enabled
        )

        dst_m.current_state = :unmounted unless m.enabled?

        # Check if it is a mount of a cloned dataset.
        datasets.each do |src, dst|
          if m.dataset_in_pool_id == src.id
            dst_m.dataset_in_pool = dst
            break
          end
        end
        # If it is not mount of a cloned dataset, than the +dst_m.dataset_in_pool+
        # may remain the same.

        if block_given? && yield(dst_m)
          dst_m.save!
          mounts << dst_m
        end
      end

      use_chain(Vps::Mounts, args: dst_vps)

      return if mounts.empty?

      append(Transactions::Utils::NoOp, args: dst_vps.node_id) do
        mounts.each { |m| create(m) }
      end
    end
  end
end
