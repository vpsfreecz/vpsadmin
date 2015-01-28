class DatasetProperty < ActiveRecord::Base
  belongs_to :pool
  belongs_to :dataset_in_pool
  belongs_to :dataset

  has_ancestry cache_depth: true

  serialize :value

  include Confirmable

  # Inherit properties from +dataset_in_pool+. Newly created properties
  # are in confirm_create state. They are returned in a hash of
  # +name+ => +property+.
  #
  # +parents+ may be a hash of the same structure. It is a list of properties
  # to inherit from. If empty, parent properties are fetched from the database.
  def self.inherit_properties!(dataset_in_pool, parents = {})
    ret = {}

    # Fetch parents if not provided
    if parents.empty?
      self.joins(:dataset_in_pool).where(
          dataset: dataset_in_pool.dataset.parent,
          dataset_in_pools: {pool_id: dataset_in_pool.pool_id}
      ).each do |p|
        parents[p.name.to_sym] = p
      end
    end

    # It's a top level dataset, fetch properties from the pool
    if parents.empty?
      self.where(pool: dataset_in_pool.pool).each do |p|
        parents[p.name.to_sym] = p
      end
    end

    VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, p|
      ret[name] = self.create!(
          dataset_in_pool: dataset_in_pool,
          dataset: dataset_in_pool.dataset,
          parent: parents[name],
          name: name,
          value: p.inheritable? ? parents[name].value : nil,
          inherited: p.inheritable?,
          confirmed: confirmed(:confirm_create)
      )
    end

    ret
  end
end
