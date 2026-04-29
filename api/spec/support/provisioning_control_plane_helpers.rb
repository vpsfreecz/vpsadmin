# frozen_string_literal: true

module ProvisioningControlPlaneHelpers
  def ensure_cluster_resource!(name)
    ClusterResource.find_by!(name: name.to_s)
  end

  def ensure_user_cluster_resources!(user:, environment:)
    ClusterResource.find_each do |resource|
      UserClusterResource.find_or_create_by!(
        user: user,
        environment: environment,
        cluster_resource: resource
      ) do |ucr|
        ucr.value = 0
      end
    end
  end

  def create_shared_package!(label:, values:)
    pkg = ClusterResourcePackage.create!(label: label)

    values.each do |resource_name, value|
      ClusterResourcePackageItem.create!(
        cluster_resource_package: pkg,
        cluster_resource: ensure_cluster_resource!(resource_name),
        value: value
      )
    end

    pkg
  end

  def create_personal_package!(user:, environment:, values:)
    pkg = ClusterResourcePackage.create!(
      label: 'Personal package',
      user: user,
      environment: environment
    )

    values.each do |resource_name, value|
      ClusterResourcePackageItem.create!(
        cluster_resource_package: pkg,
        cluster_resource: ensure_cluster_resource!(resource_name),
        value: value
      )
    end

    UserClusterResourcePackage.create!(
      cluster_resource_package: pkg,
      user: user,
      environment: environment,
      added_by: SpecSeed.admin,
      comment: 'personal'
    )

    user.calculate_cluster_resources_in_env(environment)
    pkg
  end

  def assign_package!(package:, user:, environment:, from_personal: false, comment: 'spec')
    previous = User.current
    User.current = SpecSeed.admin
    package.assign_to(
      environment,
      user,
      comment: comment,
      from_personal: from_personal
    )
  ensure
    User.current = previous
  end

  def create_environment_user_config!(environment:, user:, default:, attrs: {})
    cfg = EnvironmentUserConfig.find_or_initialize_by(
      environment: environment,
      user: user
    )

    cfg.assign_attributes(
      {
        default: default,
        can_create_vps: environment.can_create_vps,
        can_destroy_vps: environment.can_destroy_vps,
        vps_lifetime: environment.vps_lifetime,
        max_vps_count: environment.max_vps_count
      }.merge(attrs)
    )
    cfg.save!
    cfg
  end

  def build_dataset_plan_fixture!(dataset_in_pool:, plan_name:, &block)
    VpsAdmin::API::DatasetPlans::Registrator.plan(
      plan_name,
      label: "Spec #{plan_name}"
    ) do |dip|
      instance_exec(dip, &block)
    end

    plan = VpsAdmin::API::DatasetPlans::Registrator.plans.fetch(plan_name)
    env_plan = EnvironmentDatasetPlan.create!(
      environment: dataset_in_pool.pool.node.location.environment,
      dataset_plan: plan.dataset_plan,
      user_add: true,
      user_remove: true
    )

    [plan, env_plan]
  end

  def repeatable_tasks_for_action(action)
    RepeatableTask.where(
      class_name: action.class.name.demodulize,
      table_name: action.class.table_name,
      row_id: action.id
    )
  end

  def dataset_actions_for_plan(dataset_in_pool:, action:)
    action_id = DatasetAction.actions.fetch(action.to_s)

    DatasetAction.where(
      pool: dataset_in_pool.pool,
      action: action_id
    )
  end
end

RSpec.configure do |config|
  config.include ProvisioningControlPlaneHelpers
end
