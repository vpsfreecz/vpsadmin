class AddResourceIpv4Private < ActiveRecord::Migration
  class ClusterResource < ActiveRecord::Base
    has_many :user_cluster_resources, dependent: :delete_all
    enum resource_type: %i(numeric object)
  end

  class UserClusterResource < ActiveRecord::Base
    belongs_to :cluster_resource
    belongs_to :user
    belongs_to :environment
  end

  class User < ActiveRecord::Base
    self.table_name = 'members'
    self.primary_key = 'm_id'
    has_many :user_cluster_resources
  end

  class Environment < ActiveRecord::Base
    has_many :user_cluster_resources
  end

  def up
    r = ClusterResource.create!(
        name: :ipv4_private,
        label: 'Private IPv4 address',
        min: 0,
        max: 32,
        stepsize: 1,
        resource_type: :object,
        allocate_chain: 'Ip::Allocate',
        free_chain: 'Ip::Free',
    )

    # Do not consider hard-deleted users
    User.where('object_state < 3').each do |u|
      Environment.all.each do |env|
        UserClusterResource.create!(
            cluster_resource: r,
            user: u,
            environment: env,
            value: 0,
        )
      end
    end
  end

  def down
    ClusterResource.find_by!(name: :ipv4_private).destroy!
  end
end
