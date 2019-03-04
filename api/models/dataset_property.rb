require_relative 'confirmable'

class DatasetProperty < ActiveRecord::Base
  belongs_to :pool
  belongs_to :dataset_in_pool
  belongs_to :dataset
  has_many :dataset_property_histories, dependent: :destroy

  has_ancestry cache_depth: true
  has_paper_trail

  serialize :value

  include Confirmable

  # Inherit properties from +dataset_in_pool+. Newly created properties
  # are in confirm_create state. They are returned in a hash of
  # +name+ => +property+.
  #
  # +parents+ may be a hash of the same structure. It is a list of properties
  # to inherit from. If empty, parent properties are fetched from the database.
  #
  # +properties+ is a hash with the same structure, but contains properties
  # that are supposed to be set to this dataset (override parent).
  def self.inherit_properties!(dataset_in_pool, parents = {}, properties = {})
    ret = {}

    # Fetch parents if not provided
    parents = find_parents(dataset_in_pool) if parents.empty?

    VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, p|
      property = self.new(
        dataset_in_pool: dataset_in_pool,
        dataset: dataset_in_pool.dataset,
        parent: parents[name],
        name: name,
        confirmed: confirmed(:confirm_create)
      )

      if properties.has_key?(name)
        property.value = properties[name]
        property.inherited = false

      else
        property.value = p.inheritable? ? parents[name].value : p.meta[:default]
        property.inherited = p.inheritable?
      end

      property.save!
      ret[name] = property
    end

    ret
  end

  def self.clone_properties!(from, to)
    ret = {}
    parents = find_parents(to)

    self.where(dataset_in_pool: from).each do |p|
      ret[p.name.to_sym] = self.create!(
        dataset_in_pool: to,
        dataset: to.dataset,
        parent: parents[p.name.to_sym],
        name: p.name,
        value: p.value,
        inherited: p.inherited,
        confirmed: confirmed(:confirm_create)
      )
    end

    ret
  end

  def self.find_parents(dataset_in_pool)
    parents = {}

    self.joins(:dataset_in_pool).where(
      dataset: dataset_in_pool.dataset.parent,
      dataset_in_pools: {pool_id: dataset_in_pool.pool_id}
    ).each do |p|
      parents[p.name.to_sym] = p
    end

    # It's a top level dataset, fetch properties from the pool
    if parents.empty?
      self.where(pool: dataset_in_pool.pool).each do |p|
        parents[p.name.to_sym] = p
      end
    end

    parents
  end

  def inheritable?
    VpsAdmin::API::DatasetProperties.property(name.to_sym).inheritable?
  end
end
