module TransactionChains
  class Ip::Update < ::TransactionChain
    label 'IP*'
    allow_empty

    # @param ip [IpAddress]
    # @param opts [Hash]
    # @option opts [User] user
    # @option opts [Environment] environment
    def link_chain(ip, opts)
      ip.lock_current!(self)
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

      reallocate_user(@ip.user, @ip.charged_environment, -1 * @ip.size) if @ip.user
      reallocate_user(user, env, @ip.size) if user
      @ip.update!(
        user:,
        charged_environment: env
      )

      return if user

      use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: {
        ips: [@ip],
        delete: true
      })
    end

    def reallocate_user(u, e, n)
      user_env = u.environment_user_configs.find_by!(
        environment: e
      )
      user_env.adjust_resource!(
        @ip.cluster_resource,
        delta: n,
        user: u,
        save: true,
        confirmed: ::ClusterResourceUse.confirmed(:confirmed)
      )
    end
  end
end
