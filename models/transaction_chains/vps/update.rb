module TransactionChains
  class Vps::Update < ::TransactionChain
    label 'Modify'
    allow_empty

    def link_chain(vps, attrs)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      opts = {}

      %i(change_reason admin_override admin_lock_type).each do |opt|
        opts[opt] = attrs[opt]
        attrs.delete(opt)
      end

      vps.assign_attributes(attrs)
      raise ActiveRecord::RecordInvalid, vps unless vps.valid?

      db_changes = {vps => {}}

      vps.changed.each do |attr|
        case attr
          when 'm_id'
            db_changes[vps][:m_id] = vps.m_id

            # VPS and all related objects must be given to the target user:
            #   - dataset and all subdatasets
            #   - IP addresses (resource allocation)
            #   - check that there is no dataset/snapshot mount of an object
            #     that does NOT belong to the target user
            #   - free/allocate cluster resources

            datasets = []

            # Chown datasets
            vps.dataset_in_pool.dataset.subtree.each do |ds|
              datasets << ds
              db_changes[ds] = {user_id: vps.m_id}
            end

            # Check mounts
            check_vps_mounts(vps, datasets)
            datasets.each { |ds| check_ds_mounts(vps, ds, vps.m_id) }

            # Transfer cluster resources
            db_changes.update(vps.transfer_resources!(vps.user))

            # Chown IP addresses
            vps.ip_addresses.where.not(user_id: nil).each do |ip|
              db_changes[ip] = {user_id: vps.m_id}
            end

          when 'vps_hostname'
            append(Transactions::Vps::Hostname, args: [vps, vps.hostname_was, vps.hostname]) do
              edit(vps, attr => vps.hostname)
            end

          when 'vps_template'
            append(Transactions::Vps::OsTemplate, args: [
                  vps,
                  ::OsTemplate.find(vps.vps_template_was),
                  vps.os_template]) do
              edit(vps, attr => vps.vps_template)
            end

          when 'dns_resolver_id'
            append(Transactions::Vps::DnsResolver, args: [vps, *find_obj(vps, attr)]) do
              edit(vps, attr => vps.dns_resolver_id)
            end

          when 'config'
            # FIXME

          when 'vps_onboot'
          when 'info', 'onstartall'
            db_changes[vps][attr] = vps.send(attr)
        end
      end

      # Note: this will not work correctly when chowning the VPS, that's
      # why it is forbidden in controller.
      resources = vps.reallocate_resources(
          attrs,
          vps.user,
          chain: self,
          override: opts[:admin_override],
          lock_type: opts[:admin_lock_type]
      )

      unless resources.empty?
        use_chain(Vps::SetResources, args: [vps, resources])
        mail(:vps_resources_change, {
            user: vps.user,
            vars: {
                vps: vps,
                admin: ::User.current,
                reason: opts[:change_reason]
            }
        }) if opts[:change_reason]
      end


      if empty?
        # Save changes immediately
        db_changes.each do |obj, changes|
          obj.update!(changes)
        end

      else
        # Changes are part of the transaction chain
        append(Transactions::Utils::NoOp, args: vps.vps_server) do
          db_changes.each do |obj, changes|
            edit(obj, changes) unless changes.empty?
          end
        end
      end

      vps
    end

    protected
    def find_obj(vps, k)
      vps.send("#{k}_change").map do |id|
        Object.const_get(k[0..-4].classify).find(id)
      end
    end

    # Check if this VPS has a mount of a dataset that is not being
    # given to the target user.
    def check_vps_mounts(vps, allowed)
      any = vps.mounts.joins(dataset_in_pool: [:dataset]).where.not(
          datasets: {id: allowed.map { |ds| ds.id }}
      ).any?

      fail 'has forbidden mount' if any
    end

    # Check that the dataset is not mounted in VPS that does not
    # belong to the target user.
    def check_ds_mounts(vps, dataset, user_id)
      dataset.dataset_in_pools.each do |dip|
        if dip.mounts.joins(:vps).where.not(
               vps: {vps_id: vps.id, m_id: user_id}
           ).any?
          fail 'is mounted elsewhere'
        end
      end
    end
  end
end
