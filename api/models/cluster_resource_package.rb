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
  # @param opts [Hash]
  # @option opts [String] :comment
  # @option opts [Boolean] :from_personal substract resources in this package
  #                                       from the user's personal package
  # @return [UserClusterResourcePackage]
  def assign_to(env, user, opts = {})
    self.class.transaction do
      ucrp = ::UserClusterResourcePackage.create!(
        cluster_resource_package: self,
        environment: env,
        user: user,
        added_by: ::User.current,
        comment: opts[:comment] || '',
      )

      if opts[:from_personal]
        personal_pkg = user.cluster_resource_packages.where(environment: env).take!
        personal_items = Hash[personal_pkg.cluster_resource_package_items.map do |it|
          [it.cluster_resource_id, it]
        end]

        cluster_resource_package_items.each do |it|
          personal_item = personal_items[it.cluster_resource_id]

          if personal_item.nil?
            raise VpsAdmin::API::Exceptions::UserResourceAllocationError,
                  "unable to add package and substract from the personal package: "+
                  "resource #{it.cluster_resource.name} not found"
          elsif personal_item.value < it.value
            raise VpsAdmin::API::Exceptions::UserResourceAllocationError,
                  "unable to add package and substract from the personal package: "+
                  "not enough #{it.cluster_resource.name} in the personal package "+
                  "(#{personal_item.value} < #{it.value})"
          end
        end

        cluster_resource_package_items.each do |it|
          personal_item = personal_items[it.cluster_resource_id]
          personal_item.value -= it.value
          personal_item.save!
        end

      else
        user.calculate_cluster_resources_in_env(env)
      end

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
