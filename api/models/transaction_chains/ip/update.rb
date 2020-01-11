module TransactionChains
  class Ip::Update < ::TransactionChain
    label 'IP*'
    allow_empty

    # @param ip [IpAddress]
    # @param opts [Hash]
    # @option opts [Integer] max_tx
    # @option opts [Integer] max_rx
    # @option opts [User] user
    # @option opts [Environment] environment
    def link_chain(ip, opts)
      @ip = ip

      if opts[:max_tx] || opts[:max_rx]
        set_shaper(opts[:max_tx], opts[:max_rx])
      end

      if opts.has_key?(:user) && ip.user != opts[:user]
        if opts[:user]
          if opts[:environment].nil?
            fail 'missing environment'
          elsif !ip.is_in_environment?(opts[:environment])
            raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation,
                  "#{ip} is not available in environment #{opts[:environment].label}"
          end
        end

        chown(opts[:user], opts[:environment])
      end
    end

    def set_shaper(tx, rx)
      if @ip.network_interface_id && (tx != @ip.max_tx || rx != @ip.max_rx)
        use_chain(Vps::ShaperChange, args:[
          @ip,
          tx || @ip.max_tx,
          rx || @ip.max_rx
        ])

      else
        @ip.update!(
          max_tx: tx,
          max_rx: rx,
        )
      end
    end

    def chown(user, env)
      reallocate_user(@ip.user, @ip.charged_environment, -1) if @ip.user
      reallocate_user(user, env, +1) if user
      @ip.update!(
        user: user,
        charged_environment: env,
      )
    end

    def reallocate_user(u, e, n)
      user_env = u.environment_user_configs.find_by!(
        environment: e,
      )
      user_env.reallocate_resource!(
        @ip.cluster_resource,
        user_env.send(@ip.cluster_resource) + n,
        user: u,
        save: true,
        confirmed: ::ClusterResourceUse.confirmed(:confirmed),
      )
    end
  end
end
