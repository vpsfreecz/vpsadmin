class AllocateIpsToUsers < ActiveRecord::Migration
  class Environment < ActiveRecord::Base
    has_many :environment_user_configs
    has_many :users, through: :environment_user_configs
    has_many :locations
  end

  class User < ActiveRecord::Base
    self.table_name = 'members'
    self.primary_key = 'm_id'

    has_many :environment_user_configs
    has_many :environments, through: :environment_user_configs
    has_many :user_cluster_resources
    has_many :vpses, foreign_key: :m_id
  end

  class EnvironmentUserConfig < ActiveRecord::Base
    belongs_to :environment
    belongs_to :user
  end

  class Location < ActiveRecord::Base
    belongs_to :environment
    has_many :nodes
  end

  class Node < ActiveRecord::Base
    self.table_name = 'servers'
    self.primary_key = 'server_id'

    belongs_to :location, foreign_key: :server_location
  end

  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'

    belongs_to :node, foreign_key: :vps_server
    belongs_to :user, foreign_key: :m_id
    has_many :ip_addresses
  end

  class Network < ActiveRecord::Base
    belongs_to :location
    has_many :ip_addresses

    enum role: %i(public_access private_access)
  end

  class IpAddress < ActiveRecord::Base
    self.table_name = 'vps_ip'
    self.primary_key = 'ip_id'

    belongs_to :network
    belongs_to :vps
    belongs_to :user
  end

  class ClusterResource < ActiveRecord::Base
    has_many :user_cluster_resources
  end

  class UserClusterResource < ActiveRecord::Base
    belongs_to :cluster_resource
    belongs_to :user
    belongs_to :environment
    has_many :cluster_resource_uses
  end

  class ClusterResourceUse < ActiveRecord::Base
    belongs_to :user_cluster_resource
  end

  class DefaultObjectClusterResouce < ActiveRecord::Base
    belongs_to :environment
    belongs_to :cluster_resource
  end

  def up
    # Reallocate resources ipv4 ipv6 ipv4_private
    # Remove ClusterResourceUse of ips by vps
    # Set ClusterResourceUse of ips to EnvironmentUserConfig

    ActiveRecord::Base.transaction do
      User.where('object_state < 3').each { |u| up_user(u) }

      DefaultObjectClusterResource.where(
          cluster_resource_id: ClusterResource.where(
              name: %w(ipv4 ipv6 ipv4_private)
          ).pluck(:id),
          class_name: 'Vps',
      ).delete_all

      ClusterResource.where(name: %i(ipv4 ipv6 ipv4_private)).update_all(
          allocate_chain: nil
      )
    end
  end

  def down
    ActiveRecord::Base.transaction do
      User.where('object_state < 3').each { |u| down_user(u) }

      ClusterResource.where(name: %i(ipv4 ipv6 ipv4_private)).update_all(
          allocate_chain: 'Ip::Allocate'
      )
    end
  end

  protected
  def up_user(u)
    %i(ipv4 ipv6 ipv4_private).each do |r_name|
      ucrs = u.user_cluster_resources.joins(:cluster_resource).where(
          cluster_resources: {name: r_name}
      )

      ucrs.each do |ucr|
        # Remove old cluster resource use
        ucr.cluster_resource_uses.delete_all(:delete_all)

        # Calculate new resource use
        user_env = u.environment_user_configs.find_by(environment: ucr.environment)
        user_env ||= EnvironmentUserConfig.create!(
            user: ucr.user,
            environment: ucr.environment,
        )

        used = 0

        q = IpAddress.joins(
            'LEFT JOIN vps ON vps.vps_id = vps_ip.vps_id'
        ).joins(network: {location: :environment}).where(
            locations: {environment_id: ucr.environment},
        )

        if ucr.environment.user_ip_ownership
          q = q.where(user: ucr.user)

        else
          q = q.where(vps: {m_id: ucr.user_id})
        end

        case ucr.cluster_resource.name.to_sym
        when :ipv4
          q = q.where(networks: {ip_version: 4, role: Network.roles[:public_access]})

        when :ipv6
          q = q.where(networks: {ip_version: 6})

        when :ipv4_private
          q = q.where(networks: {ip_version: 4, role: Network.roles[:private_access]})
        end

        used += q.count

        ClusterResourceUse.create!(
            user_cluster_resource: ucr,
            class_name: 'EnvironmentUserConfig',
            table_name: 'environment_user_configs',
            row_id: user_env.id,
            value: used,
            confirmed: 1,
        )
      end
    end
  end

  def down_user(u)
    %i(ipv4 ipv6 ipv4_private).each do |r_name|
      ucrs = u.user_cluster_resources.joins(:cluster_resource).where(
          cluster_resources: {name: r_name}
      )

      ucrs.each do |ucr|
        # Remove old cluster resource use
        ucr.cluster_resource_uses.delete_all(:delete_all)
      end

      # Calculate new resource use
      u.vpses.where('object_state < 3').each do |vps|
        q = vps.ip_addresses.joins(:network)

        case r_name
        when :ipv4
          q = q.where(networks: {ip_version: 4, role: Network.roles[:public_access]})

        when :ipv6
          q = q.where(networks: {ip_version: 6})

        when :ipv4_private
          q = q.where(networks: {ip_version: 4, role: Network.roles[:private_access]})
        end

        ClusterResourceUse.create!(
            user_cluster_resource: u.user_cluster_resources.joins(:cluster_resource).find_by!(
                environment: vps.node.location.environment,
                cluster_resources: {name: r_name},
                user: u,
            ),
            class_name: 'Vps',
            table_name: 'vps',
            row_id: vps.id,
            value: q.count,
            confirmed: 1,
        )
      end
    end
  end
end
