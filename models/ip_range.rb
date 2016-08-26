class IpRange < Network
  after_save :ensure_ip_addresses

  # @param net [::Network]
  # @param opts [Hash]
  # @option opts [::User] user
  def self.from_network(net, opts)
    net.get_or_create_range(opts)
  end

  def network
    parent
  end

  def size
    super + 2
  end

  def chown(user)
    self.class.transaction do
      if ip_addresses.where.not(vps: nil).count > 0
        fail 'IP range in use'
      end

      reallocate_resource(self.user, -size) if self.user
      reallocate_resource(user, +size) if user

      self.user = user
      ip_addresses.update_all(user_id: user.id)
      save!
    end
  end

  protected
  def ensure_ip_addresses
    net_addr do |net|
      net.each do |ip|
        begin
          ::IpAddress.register(
              ip.address,
              network: self,
              user: self.user,
          )

        rescue ActiveRecord::RecordInvalid => e
          raise e if (e.record.errors.keys - %i(ip_addr)).any?
        end
      end
    end
  end

  def reallocate_resource(user, n)
    user_env = user.environment_user_configs.where(
        environment: location.environment,
    ).take!

    user_env.reallocate_resource!(
        cluster_resource,
        user_env.send(cluster_resource) + n,
        user: user,
        save: true,
        confirmed: ::ClusterResourceUse.confirmed(:confirmed),
    )
  end
end
