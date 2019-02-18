class UserClusterResourcePackage < ::ActiveRecord::Base
  belongs_to :environment
  belongs_to :user
  belongs_to :cluster_resource_package
  belongs_to :added_by, foreign_key: :added_by_id, class_name: 'User'

  after_destroy :recalculate_user_cluster_resources

  def label
    cluster_resource_package.label
  end

  def can_destroy?
    cluster_resource_package.can_destroy?
  end

  def is_personal
    cluster_resource_package.is_personal
  end

  protected
  def recalculate_user_cluster_resources
    user.calculate_cluster_resources_in_env(environment)
  end
end
