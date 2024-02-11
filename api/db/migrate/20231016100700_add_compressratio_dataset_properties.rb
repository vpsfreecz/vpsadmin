class AddCompressratioDatasetProperties < ActiveRecord::Migration[7.0]
  class DatasetProperty < ActiveRecord::Base
    has_ancestry cache_depth: true
    serialize :value
  end

  def up
    %w[compressratio refcompressratio].each do |new_prop_name|
      # Pool properties
      pool_parents = {}

      DatasetProperty.roots.group(:pool_id).each do |prop|
        pool_parents[prop.pool_id] = DatasetProperty.create!(
          pool_id: prop.pool_id,
          dataset_id: nil,
          dataset_in_pool_id: nil,
          parent: nil,
          name: new_prop_name,
          value: 1.0,
          inherited: false,
          confirmed: prop.confirmed
        )
      end

      # Dataset properties
      DatasetProperty.where.not(dataset_id: nil).group(:dataset_id).arrange.each do |prop, children|
        prop_parent = prop.parent
        pool_parent = prop_parent && pool_parents[prop_parent.pool_id]
        create_property(new_prop_name, pool_parent, prop, children)
      end
    end
  end

  def down
    DatasetProperty.where(name: %w[compressratio refcompressratio]).delete_all
  end

  protected

  def create_property(new_prop_name, parent, prop, children)
    new_prop = DatasetProperty.create!(
      pool_id: prop.pool_id,
      dataset_id: prop.dataset_id,
      dataset_in_pool_id: prop.dataset_in_pool_id,
      parent: parent,
      name: new_prop_name,
      value: 1.0,
      inherited: false,
      confirmed: prop.confirmed
    )

    children.each do |child_prop, grandchildren|
      create_property(new_prop_name, new_prop, child_prop, grandchildren)
    end
  end
end
