module TransactionChains
  class Ip::Update < ::TransactionChain
    label 'IP*'
    allow_empty

    # @param ip [IpAddress]
    # @param opts [Hash]
    # @option opts [Integer] max_tx
    # @option opts [Integer] max_rx
    # @option opts [User] user
    def link_chain(ip, opts)
      @ip = ip

      if opts[:max_tx] || opts[:max_rx]
        set_shaper(opts[:max_tx], opts[:max_rx])
      end

      if opts.has_key?(:user) && ip.user != opts[:user]
        chown(opts[:user])
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

    def chown(user)
      reallocate_user(@ip.user, -1) if @ip.user
      reallocate_user(user, +1) if user
      @ip.update!(user: user)
    end

    def reallocate_user(u, n)
      user_env = u.environment_user_configs.find_by!(
        environment: @ip.network.location.environment,
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
