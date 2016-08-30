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

            # Chown datasets and transfer cluster resources
            vps.dataset_in_pool.dataset.subtree.each do |ds|
              datasets << ds
              db_changes[ds] = {user_id: vps.m_id}

              dip = ds.primary_dataset_in_pool!
              db_changes.update(dip.transfer_resources!(vps.user))
            end

            # Check mounts
            check_vps_mounts(vps, datasets)
            datasets.each { |ds| check_ds_mounts(vps, ds, vps.m_id) }

            # Transfer cluster resources
            ## CPU, memory, swap
            db_changes.update(vps.transfer_resources!(vps.user))
            
            ## IP addresses
            db_changes.update(transfer_ip_addresses(vps))

          when 'vps_hostname'
            append(Transactions::Vps::Hostname, args: [vps, vps.hostname_was, vps.hostname]) do
              edit(vps, {attr => vps.hostname, 'manage_hostname' => true})
              just_create(vps.log(:hostname, {
                  :manage_hostname => true,
                  :hostname => vps.hostname
              }))
            end

          when 'manage_hostname'
            unless vps.manage_hostname
              append(Transactions::Vps::UnmanageHostname, args: vps) do
                edit(vps, attr => vps.manage_hostname)
              just_create(vps.log(:hostname, {:manage_hostname => false}))
              end
            end

          when 'vps_template'
            append(Transactions::Vps::OsTemplate, args: [
                  vps,
                  ::OsTemplate.find(vps.vps_template_was),
                  vps.os_template]) do
              edit(vps, attr => vps.vps_template)
              just_create(vps.log(:os_template, {
                  id: vps.vps_template,
                  name: vps.os_template.name,
                  label: vps.os_template.label,
              }))
            end

          when 'dns_resolver_id'
            append(Transactions::Vps::DnsResolver, args: [vps, *find_obj(vps, attr)]) do
              edit(vps, attr => vps.dns_resolver_id)
              just_create(vps.log(:dns_resolver, {
                  id: vps.dns_resolver_id,
                  addr: vps.dns_resolver.addr,
                  label: vps.dns_resolver.dns_label,
              }))
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
        append(Transactions::Utils::NoOp, args: find_node_id) do
          data = {}

          resources.each do |use|
            data[ use.user_cluster_resource.cluster_resource.name ] = use.value
          end

          just_create(vps.log(:resources, data))
        end

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

    # Frees IP addresses of +vps+ from current owner and allocates them to the
    # new one.
    def transfer_ip_addresses(vps)
      ret = {}
      src_env = ::User.find(vps.user_id_was).environment_user_configs.find_by!(
          environment: vps.node.location.environment,
      )
      dst_env = vps.user.environment_user_configs.find_by!(
          environment: vps.node.location.environment,
      )
      
      %i(ipv4 ipv4_private ipv6).each do |r|
        st_cnt, st_changes = standalone_ips(vps, r)
        r_cnt, r_changes = range_ips(vps, r)

        cnt = st_cnt + r_cnt
        ret.update(st_changes)
        ret.update(r_changes)

        next if cnt == 0

        src_use = src_env.reallocate_resource!(
            r,
            src_env.send(r) - cnt,
            user: src_env.user,
            confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )
        
        dst_use = dst_env.reallocate_resource!(
            r,
            dst_env.send(r) + cnt,
            user: dst_env.user,
            confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )

        ret[src_use] = {value: src_use.value}
        ret[dst_use] = {value: dst_use.value}
      end

      ret
    end

    def standalone_ips(vps, r)
      q = vps.ip_addresses.joins(:network).where(
          networks: {type: 'Network'}
      )

      case r
      when :ipv4
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:public_access]})
      
      when :ipv4_private
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:private_access]})
      
      when :ipv6
        q = q.where(networks: {ip_version: 6})
      end

      changes = {}
      q.each { |ip| changes[ip] = {user_id: vps.m_id} }

      [q.count, changes]
    end

    def range_ips(vps, r)
      q = vps.ip_addresses.joins(:network).where(
          networks: {type: 'IpRange'}
      )

      case r
      when :ipv4
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:public_access]})
      
      when :ipv4_private
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:private_access]})
      
      when :ipv6
        q = q.where(networks: {ip_version: 6})
      end

      cnt = 0
      changes = {}
      
      # Check that all ranges can be chowned
      q.includes(:network).group('networks.id').each do |ip|
        if ip.network.ip_addresses.where('vps_id != ? AND vps_id IS NOT NULL', vps.id).any?
          fail "range #{ip.network} is not exclusive to VPS #{vps.id}"
        end
        
        cnt += ip.network.size
        changes[ip.network] = {user_id: vps.m_id}

        ip.network.ip_addresses.each { |ip| changes[ip] = {user_id: vps.m_id} }
      end

      [cnt, changes]
    end
  end
end
