require 'vpsadmin/api/maintainable'
require 'vpsadmin/api/dataset_properties'
require_relative 'lockable'

class Pool < ActiveRecord::Base
  belongs_to :node
  has_many :dataset_in_pools
  has_many :dataset_properties
  has_many :dataset_actions
  has_many :snapshot_downloads

  enum role: %i[hypervisor primary backup]

  STATE_VALUES = %i[unknown online degraded suspended faulted error].freeze
  SCAN_VALUES = %i[unknown none scrub resilver error].freeze

  enum state: STATE_VALUES, _prefix: :state
  enum scan: SCAN_VALUES, _prefix: :scan

  validates :node_id, :label, :filesystem, :role, presence: true

  include Lockable
  include VpsAdmin::API::DatasetProperties::Model

  include VpsAdmin::API::Maintainable::Model
  include VpsAdmin::API::Maintainable::Check

  maintenance_parents :node

  def self.create!(attrs, properties)
    pool = new(attrs)
    TransactionChains::Pool::Create.fire(pool, properties)
  end

  # @param node [::Node]
  # @param role [:hypervisor, :primary]
  # @return [Array<::Pool>]
  def self.pick_by_node(node, role: nil)
    q =
      joins('LEFT JOIN dataset_in_pools ON dataset_in_pools.pool_id = pools.id')
      .where(
        'pools.max_datasets > 0
        AND pools.is_open = 1
        AND pools.maintenance_lock = 0
        AND pools.node_id = ?',
        node.id
      )

    q = q.where(role: role.to_s) if role

    q
      .group('pools.id')
      .order(Arel.sql('COUNT(dataset_in_pools.id) / pools.max_datasets ASC'))
      .to_a
  end

  # @param node [::Node]
  # @param role [:hypervisor, :primary]
  # @return [::Pool]
  def self.take_by_node!(node, role: nil)
    pool, = pick_by_node(node, role:)
    raise "no pool available on #{node.domain_name}" if pool.nil?

    pool
  end

  def name
    i = filesystem.index('/')

    if i.nil?
      filesystem
    else
      filesystem[0..(i - 1)]
    end
  end

  def state_value
    STATE_VALUES[self.class.states[state]].to_s
  end

  def scan_value
    SCAN_VALUES[self.class.scans[scan]].to_s
  end
end
