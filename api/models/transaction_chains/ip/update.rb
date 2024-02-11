module TransactionChains
  class Ip::Update < ::TransactionChain
    label 'IP*'
    allow_empty

    # @param ip [IpAddress]
    # @param opts [Hash]
    # @option opts [User] user
    # @option opts [Environment] environment
    def link_chain(ip, opts)
      @ip = ip

      return unless opts.has_key?(:user) && ip.user != opts[:user]

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
      reallocate_user(@ip.user, @ip.charged_environment, -1 * @ip.size) if @ip.user
      reallocate_user(user, env, @ip.size) if user
      @ip.update!(
        user:,
        charged_environment: env
      )
    end

    def reallocate_user(u, e, n)
      user_env = u.environment_user_configs.find_by!(
        environment: e
      )
      user_env.reallocate_resource!(
        @ip.cluster_resource,
        user_env.send(@ip.cluster_resource) + n,
        user: u,
        save: true,
        confirmed: ::ClusterResourceUse.confirmed(:confirmed)
      )
    end
  end
end
