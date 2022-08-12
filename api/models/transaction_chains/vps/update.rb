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
        when 'user_id'
          chown_vps(vps, ::User.find(vps.user_id_was))

        when 'hostname'
          append(Transactions::Vps::Hostname, args: [vps, vps.hostname_was, vps.hostname]) do
            edit(vps, {attr => vps.hostname, 'manage_hostname' => true})
            just_create(vps.log(:hostname, {
              manage_hostname: true,
              hostname: vps.hostname,
            }))
          end

        when 'manage_hostname'
          unless vps.manage_hostname
            append(Transactions::Vps::UnmanageHostname, args: vps) do
              edit(vps, attr => vps.manage_hostname)
            just_create(vps.log(:hostname, {:manage_hostname => false}))
            end
          end

        when 'os_template_id'
          append(Transactions::Vps::OsTemplate, args: [
              vps,
              ::OsTemplate.find(vps.os_template_id_was),
              vps.os_template
          ]) do
            edit(vps, attr => vps.os_template_id)
            just_create(vps.log(:os_template, {
              id: vps.os_template_id,
              name: vps.os_template.name,
              label: vps.os_template.label,
            }))
          end

        when 'dns_resolver_id'
          if vps.dns_resolver_id
            append_t(
              Transactions::Vps::DnsResolver,
              args: [vps, *find_obj(vps, attr, accept_nil: true)],
            ) do |t|
              t.edit(vps, attr => vps.dns_resolver_id)
              t.just_create(vps.log(:dns_resolver, {
                manage_dns_resolver: true,
                id: vps.dns_resolver_id,
                addr: vps.dns_resolver.addr,
                label: vps.dns_resolver.label,
              }))
            end
          else
            append_t(
              Transactions::Vps::UnmanageDnsResolver,
              args: [vps, ::DnsResolver.find(vps.dns_resolver_id_was)],
            ) do |t|
              t.edit(vps, attr => nil)
              t.just_create(vps.log(:dns_resolver, {
                manage_dns_resolver: false,
              }))
            end
          end

        when 'cpu_limit'
          db_changes[vps][attr] = vps.send(attr) == 0 ? nil : vps.send(attr)

        when 'start_menu_timeout'
          append_t(
            Transactions::Vps::StartMenu,
            args: [vps, vps.start_menu_timeout_was],
          ) do |t|
            t.edit(vps, start_menu_timeout: vps.start_menu_timeout)
            t.just_create(vps.log(:start_menu, {
              timeout: vps.start_menu_timeout,
            }))
          end

        when 'config'
          # FIXME

        when 'onboot'
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

      if !resources.empty? || vps.cpu_limit_changed?
        append(Transactions::Utils::NoOp, args: find_node_id) do
          data = {}

          resources.each do |use|
            data[ use.user_cluster_resource.cluster_resource.name ] = use.value
          end

          data['cpu_limit'] = vps.cpu_limit if vps.cpu_limit_changed?

          just_create(vps.log(:resources, data))
        end

        use_chain(Vps::SetResources, args: [vps, resources])
        mail(:vps_resources_change, {
          user: vps.user,
          vars: {
            vps: vps,
            admin: ::User.current,
            reason: opts[:change_reason],
          }
        }) if opts[:change_reason]
      end

      return vps if db_changes.empty?

      if empty?
        # Save changes immediately
        db_changes.each do |obj, changes|
          obj.update!(changes)
        end

      else
        # Changes are part of the transaction chain
        append(Transactions::Utils::NoOp, args: vps.node_id) do
          db_changes.each do |obj, changes|
            edit(obj, changes) unless changes.empty?
          end
        end
      end

      vps
    end

    protected
    def find_obj(vps, k, accept_nil: false)
      vps.send("#{k}_change").map do |id|
        next(nil) if id.nil? && accept_nil
        Object.const_get(k[0..-4].classify).find(id)
      end
    end

    def chown_vps(vps, orig_user)
      db_changes = {vps => {user_id: vps.user_id}}

      # VPS and all related objects must be given to the target user:
      #   - dataset and all subdatasets
      #   - IP addresses (resource allocation)
      #   - check that there is no dataset/snapshot mount of an object
      #     that does NOT belong to the target user
      #   - remove IPs from previous owner's nfs exports
      #   - add IPs to new owner's nfs exports
      #   - transfer exports of VPS's datasets / snapshots
      #   - free/allocate cluster resources

      if vps.node.vpsadminos?
        cur_userns_map = vps.userns_map
        new_userns_map = ::UserNamespaceMap.joins(:user_namespace).where(
          user_namespaces: {user_id: vps.user_id}
        ).take!

        use_chain(UserNamespaceMap::Use, args: [new_userns_map, vps.node])
      else
        cur_userns_map = nil
        new_userns_map = nil
      end

      datasets = []

      # Chown datasets and transfer cluster resources
      vps.dataset_in_pool.dataset.subtree.each do |ds|
        datasets << ds
        db_changes[ds] = {user_id: vps.user_id}

        dip = ds.primary_dataset_in_pool!
        db_changes.update(dip.transfer_resources!(vps.user))

        db_changes[dip] ||= {}
        db_changes[dip].update({
          user_namespace_map_id: new_userns_map && new_userns_map.id,
        })
      end

      # Check mounts
      check_vps_mounts(vps, datasets)
      datasets.each { |ds| check_ds_mounts(vps, ds, vps.user_id) }

      # Transfer cluster resources
      ## CPU, memory, swap
      db_changes.update(vps.transfer_resources!(vps.user))

      ## IP addresses
      db_changes.update(transfer_ip_addresses(vps))

      # Chown user namespace mapping
      if vps.node.vpsadminos?
        append_t(Transactions::Vps::Chown, args: [
          vps, vps.userns_map, new_userns_map
        ]) do |t|
          db_changes.each do |obj, changes|
            t.edit(obj, changes) unless changes.empty?
          end

          t.just_create(vps.log(:user, {
            user_id: vps.user_id,
          }))
        end

        use_chain(
          UserNamespaceMap::Disuse,
          args: [vps],
          kwargs: {userns_map: cur_userns_map},
        )
      end

      # Transfer exports of the VPS's own datasets / snapshots
      chown_exports = []

      datasets.each do |ds|
        ds.dataset_in_pools.each do |dip|
          dip.exports.each do |ex|
            # Remove hosts belonging to the original user
            hosts_to_delete = ex.export_hosts.to_a.select do |host|
              host.ip_address.network_interface.vps_id != vps.id
            end

            if hosts_to_delete.any?
              use_chain(Export::DelHosts, args: [ex, hosts_to_delete])
            end

            # Add hosts belonging to the target user
            add_hosts_to_chowned_export(ex, vps.user) if ex.all_vps

            chown_exports << ex
          end
        end
      end

      if chown_exports.any?
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          chown_exports.each do |ex|
            t.edit(ex, user_id: vps.user_id)
          end
        end
      end

      # Remove export hosts from all exports of the original user
      ::Export.where(user: orig_user).each do |ex|
        next if chown_exports.include?(ex)

        use_chain(Export::DelHosts, args: [ex, vps.ip_addresses])
      end

      # Add export hosts to all exports of the target user
      use_chain(Export::AddHostsToAll, args: [vps.user, vps.ip_addresses])

      if vps.node.openvz?
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          db_changes.each do |obj, changes|
            edit(obj, changes) unless changes.empty?
          end

          t.just_create(vps.log(:user, {
            user_id: vps.user_id,
          }))
        end
      end
    end

    def add_hosts_to_chowned_export(export, user)
      ips = ::IpAddress.joins(:network, network_interface: :vps).where(
        networks: {ip_version: 4},
        vpses: {user_id: user.id},
      ).to_a

      add_hosts = ips.map do |ip|
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

      if add_hosts.any?
        append_t(Transactions::Export::AddHosts, args: [export, add_hosts]) do |t|
          add_hosts.each { |host| t.just_create(host) }
        end
      end
    end

    # Check if this VPS has a mount of a dataset that is not being
    # given to the target user.
    def check_vps_mounts(vps, allowed)
      forbidden_mounts = vps.mounts.joins(dataset_in_pool: [:dataset]).where.not(
        datasets: {id: allowed.map { |ds| ds.id }}
      )

      if forbidden_mounts.any?
        fail "has forbidden mounts: #{forbidden_mounts.map { |mnt| mnt.dst }.join('; ')}"
      end
    end

    # Check that the dataset is not mounted in VPS that does not
    # belong to the target user.
    def check_ds_mounts(vps, dataset, user_id)
      dataset.dataset_in_pools.each do |dip|
        dip.mounts.each do |mnt|
          next if mnt.vps == vps || mnt.vps.user.id == user_id

          fail "dataset #{dataset.full_name} is mounted in VPS #{mnt.vps_id}"
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

        cnt = st_cnt
        ret.update(st_changes)

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
      q = vps.ip_addresses.joins(:network)

      case r
      when :ipv4
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:public_access]})

      when :ipv4_private
        q = q.where(networks: {ip_version: 4, role: ::Network.roles[:private_access]})

      when :ipv6
        q = q.where(networks: {ip_version: 6})
      end

      changes = {}

      if vps.node.location.environment.user_ip_ownership
        q.each { |ip| changes[ip] = {user_id: vps.user_id} }
      end

      [q.count, changes]
    end
  end
end
