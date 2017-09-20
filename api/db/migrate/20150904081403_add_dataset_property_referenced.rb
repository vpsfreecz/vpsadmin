class AddDatasetPropertyReferenced < ActiveRecord::Migration
  class Pool < ActiveRecord::Base
    has_many :dataset_in_pools
  end

  class Dataset < ActiveRecord::Base
    has_many :dataset_in_pools
    has_many :dataset_properties
    has_ancestry cache_depth: true
  end

  class DatasetInPool < ActiveRecord::Base
    belongs_to :pool
    belongs_to :dataset
    has_many :dataset_properties
  end

  class DatasetProperty < ActiveRecord::Base
    belongs_to :dataset
    belongs_to :dataset_in_pool
    serialize :value
    has_ancestry cache_depth: true
  end

  def up
    pool_props = {}

    Pool.all.each do |pool|
      pool_props[pool.id] = DatasetProperty.create!(
          pool_id: pool.id,
          parent: nil,
          name: :referenced,
          value: 0,
          confirmed: 1
      )
    end

    DatasetInPool.includes(:dataset).joins(:pool).where(
        pools: {role: [0, 1]} # hypervisor and primary pools only
    ).each do |dip|
      parent_prop = DatasetProperty.joins(:dataset_in_pool).where(
          dataset: dip.dataset.parent,
          name: :referenced,
          dataset_in_pools: {pool_id: dip.pool_id}
      ).take

      parent_prop = pool_props[dip.pool_id] unless parent_prop

      DatasetProperty.create!(
          dataset_id: dip.dataset_id,
          dataset_in_pool_id: dip.id,
          parent: parent_prop,
          name: :referenced,
          value: 0,
          confirmed: 1
      )
    end
  end

  def down
    DatasetProperty.where(name: :referenced).delete_all
  end
end
