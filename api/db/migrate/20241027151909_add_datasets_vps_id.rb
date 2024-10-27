class AddDatasetsVpsId < ActiveRecord::Migration[7.1]
  class Vps < ActiveRecord::Base
    belongs_to :dataset_in_pool
  end

  class Dataset < ActiveRecord::Base
    has_many :dataset_in_pools
    has_ancestry cache_depth: true
  end

  class DatasetInPool < ActiveRecord::Base
    belongs_to :dataset
  end

  def change
    add_column :datasets, :vps_id, :bigint, null: true
    add_index :datasets, :vps_id

    reversible do |dir|
      dir.up do
        Vps.where('object_state < 3').each do |vps|
          next if vps.dataset_in_pool.nil?

          vps.dataset_in_pool.dataset.subtree.update_all(vps_id: vps.id)
        end
      end
    end
  end
end
