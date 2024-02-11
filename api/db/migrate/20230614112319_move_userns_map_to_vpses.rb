class MoveUsernsMapToVpses < ActiveRecord::Migration[7.0]
  class Vps < ActiveRecord::Base
    belongs_to :dataset_in_pool
  end

  class Dataset < ActiveRecord::Base
    has_many :dataset_in_pools
    has_ancestry cache_depth: true

    def primary_dataset_in_pool!
      dataset_in_pools.joins(:pool).where.not(pools: { role: 2 }).take!
    end
  end

  class Pool < ActiveRecord::Base
    has_many :dataset_in_pools
  end

  class DatasetInPool < ActiveRecord::Base
    belongs_to :dataset
    belongs_to :pool
    has_many :vpses
  end

  def change
    add_column :vpses, :user_namespace_map_id, :integer, null: true
    add_index :vpses, :user_namespace_map_id

    reversible do |dir|
      dir.up do
        # Sets VPS userns map to its dataset in pool userns map. In theory,
        # VPS subdatasets could have different maps... we don't deal with that,
        # as in practice it's not the case.
        # We also discard userns maps set on non-VPS datasets.
        Vps.where('object_state < 3').each do |vps|
          next if vps.dataset_in_pool.nil?

          vps.update!(user_namespace_map_id: vps.dataset_in_pool.user_namespace_map_id)
        end
      end

      dir.down do
        # Set userns map back on dataset in pools
        Vps.where('object_state < 3').each do |vps|
          next if vps.dataset_in_pool.nil?

          vps.dataset_in_pool.dataset.subtree.each do |ds|
            begin
              dip = ds.primary_dataset_in_pool!
            rescue ActiveRecord::RecordNotFound
              next
            end

            dip.update!(user_namespace_map_id: vps.user_namespace_map_id)
          end
        end
      end
    end

    remove_index :dataset_in_pools, :user_namespace_map_id
    remove_column :dataset_in_pools, :user_namespace_map_id, :integer, null: true
  end
end
