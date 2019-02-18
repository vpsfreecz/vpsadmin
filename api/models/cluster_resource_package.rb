class ClusterResourcePackage < ActiveRecord::Base
  has_many :cluster_resource_package_items, dependent: :delete_all
  has_many :default_user_cluster_resource_packages, dependent: :delete_all
  has_many :user_cluster_resource_packages, dependent: :destroy
  belongs_to :environment
  belongs_to :user

  validates :label, presence: true, length: {minimum: 2}
  validate :check_package_type

  # @param resource [::ClusterResource]
  # @param value [Integer]
  # @return [ClusterResourcePackageItem]
  def add_item(resource, value)
    self.class.transaction do
      it = ClusterResourcePackageItem.create!(
        cluster_resource_package: self,
        cluster_resource: resource,
        value: value,
      )

      recalculate_user_resources
    end
  end

  # @param item [ClusterResourcePackageItem]
  # @return [ClusterResourcePackageItem]
  def update_item(item, value)
    self.class.transaction do
      item.update!(value: value)
      recalculate_user_resources
      item
    end
  end

  # @param item [ClusterResourcePackageItem]
  def remove_item(item)
    self.class.transaction do
      item.destroy!
      recalculate_user_resources
    end
  end

  # @param env [::Environment]
  # @param user [::User]
  # @param comment [String]
  # @return [UserClusterResourcePackage]
  def assign_to(env, user, comment)
    self.class.transaction do
      ucrp = ::UserClusterResourcePackage.create!(
        cluster_resource_package: self,
        environment: env,
        user: user,
        added_by: ::User.current,
        comment: comment,
      )

      user.calculate_cluster_resources_in_env(env)
      ucrp
    end
  end

  def can_destroy?
    !is_personal
  end

  def is_personal
    (user_id && environment_id) ? true : false
  end

  protected
  def check_package_type
    if environment_id && !user_id
      errors.add(:user_id, 'user_id and environment_id must be used together')

    elsif !environment_id && user_id
      errors.add(:environment_id, 'environment_id and user_id must be used together')
    end
  end

  def recalculate_user_resources
    user_cluster_resource_packages.group('user_id, environment_id').each do |user_pkg|
      user_pkg.user.calculate_cluster_resources_in_env(user_pkg.environment)
    end
  end
end
