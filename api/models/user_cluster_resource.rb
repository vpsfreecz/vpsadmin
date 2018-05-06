class UserClusterResource < ActiveRecord::Base
  include Lockable

  belongs_to :user
  belongs_to :environment
  belongs_to :cluster_resource

  has_paper_trail

  def used
    return @used if @used

    @used = ::ClusterResourceUse.joins(:user_cluster_resource).where(
      user_cluster_resources: {
        user_id: user_id,
        environment_id: environment_id,
        cluster_resource_id: cluster_resource_id
      },
      cluster_resource_uses: {
        confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        enabled: true
      }
    ).sum(:value)
  end

  def free
    value - used
  end
end
