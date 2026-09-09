module TransactionChains
  class Ip::Update < ::TransactionChain
    label 'IP*'
    allow_empty

    # @param ip [IpAddress]
    # @param opts [Hash]
    # @option opts [User] user
    # @option opts [Environment] environment
    def link_chain(ip, opts)
      lock(ip)
      ip.reload(lock: true)
      @ip = ip

      return unless opts.has_key?(:user) && ip.user != opts[:user]

      vps = ip.network_interface&.vps
      if vps && vps.node.location.environment.user_ip_ownership
        raise VpsAdmin::API::Exceptions::IpAddressInUse, 'cannot chown IP while it belongs to a VPS'
      end

      if opts[:user]
        if opts[:environment].nil?
          raise 'missing environment'
        elsif !ip.is_in_environment?(opts[:environment])
          raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation,
                "#{ip} is not available in environment #{opts[:environment].label}"
        end
      end

      chown(opts[:user], opts[:environment])
    end

    def chown(user, env)
      @ip.ensure_charge_environment!

      configs = [[@ip.user, @ip.charged_environment], [user, env]].filter_map do |owner, environment|
        owner&.environment_user_configs&.find_by!(environment:)
      end
      configs.uniq(&:id).sort_by(&:id).each(&:lock!)
      before_cleanup = last_id
      unless user
        use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: { ips: [@ip], delete: true })
      end

      # Cleanup can restore DNS and host records on rollback. Keep ownership
      # and accounting until its final successful confirmation, with the quota
      # lock preventing a competing deferred total from overwriting this one.
      if !user && last_id != before_cleanup
        use = reallocate_user(@ip.user, @ip.charged_environment, -@ip.size, deferred: true) if @ip.user
        confirmation = nil
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.edit(@ip, user_id: nil, charged_environment_id: nil)
          t.edit(use, value: use.value) if use
          confirmation = t
        end
        return confirmation
      end

      reallocate_user(@ip.user, @ip.charged_environment, -@ip.size) if @ip.user
      reallocate_user(user, env, @ip.size) if user
      @ip.update!(
        user:,
        charged_environment: env
      )
      nil
    end

    def reallocate_user(u, e, n, deferred: false)
      user_env = u.environment_user_configs.find_by!(
        environment: e
      )
      user_env.reallocate_resource!(
        @ip.cluster_resource,
        delta: n,
        user: u,
        save: !deferred,
        chain: deferred ? self : nil,
        confirmed: ::ClusterResourceUse.confirmed(:confirmed)
      )
    end
  end
end
