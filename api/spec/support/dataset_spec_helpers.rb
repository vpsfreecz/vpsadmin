# frozen_string_literal: true

require 'securerandom'

module DatasetSpecHelpers
  # Ensure the pool has a default value for every dataset property.
  # These are used when inheriting properties for top-level datasets.
  def seed_pool_dataset_properties!(pool)
    VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, prop|
      DatasetProperty.find_or_create_by!(
        pool: pool,
        dataset_in_pool_id: nil,
        dataset_id: nil,
        name: name.to_s
      ) do |p|
        p.value = prop.meta[:default]
        p.inherited = false
        p.confirmed = DatasetProperty.confirmed(:confirmed)
      end
    end
  end

  # Create a dataset and one DatasetInPool on the given pool.
  # Also creates per-dataset DatasetProperty rows via inherit_properties!.
  #
  # NOTE: We avoid quota/refquota changes in these tests unless explicitly needed,
  # to keep cluster-resource allocation out of scope.
  def create_dataset_with_pool!(
    user:,
    pool:,
    name:,
    label: nil,
    parent: nil,
    user_editable: true,
    user_create: true,
    user_destroy: true,
    properties: {}
  )
    seed_pool_dataset_properties!(pool)

    ds = Dataset.create!(
      user: user,
      name: name,
      parent: parent,
      user_editable: user_editable,
      user_create: user_create,
      user_destroy: user_destroy,
      confirmed: Dataset.confirmed(:confirmed)
    )

    dip = DatasetInPool.create!(
      dataset: ds,
      pool: pool,
      label: label,
      confirmed: DatasetInPool.confirmed(:confirmed)
    )

    DatasetProperty.inherit_properties!(dip, {}, properties.transform_keys(&:to_sym))

    [ds, dip]
  end

  def create_snapshot!(dataset:, dip:, name: nil, label: nil, confirmed: :confirmed, reference_count: 0)
    name ||= "snap-#{SecureRandom.hex(4)}"

    snap = Snapshot.create!(
      dataset: dataset,
      name: name,
      label: label,
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(confirmed)
    )

    sip = SnapshotInPool.create!(
      snapshot: snap,
      dataset_in_pool: dip,
      reference_count: reference_count,
      confirmed: SnapshotInPool.confirmed(confirmed)
    )

    [snap, sip]
  end

  # Returns [dataset_plan, env_dataset_plan]
  def create_daily_backup_env_plan!(environment:, user_add: true, user_remove: true)
    plan = VpsAdmin::API::DatasetPlans.plans[:daily_backup]
    plan.instance_variable_set(:@dataset_plan, nil)
    dp = plan.send(:dataset_plan)

    edp = EnvironmentDatasetPlan.find_or_create_by!(
      environment: environment,
      dataset_plan: dp
    ) do |p|
      p.user_add = user_add
      p.user_remove = user_remove
    end

    if edp.user_add != user_add || edp.user_remove != user_remove
      edp.update!(user_add: user_add, user_remove: user_remove)
    end

    [dp, edp]
  end
end

RSpec.configure do |config|
  config.include DatasetSpecHelpers
end
