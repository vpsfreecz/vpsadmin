require 'vpsadmin/api/maintainable'
require 'vpsadmin/api/dataset_properties'
require_relative 'lockable'

class Pool < ApplicationRecord
  belongs_to :node
  has_many :dataset_in_pools
  has_many :dataset_properties
  has_many :dataset_actions
  has_many :snapshot_downloads

  enum :role, %i[hypervisor primary backup]

  STATE_VALUES = %i[unknown online degraded suspended faulted error].freeze
  SCAN_VALUES = %i[unknown none scrub resilver error].freeze
  ALLOCATION_STATUS_MAX_AGE = 900
  PROJECTED_FILL_SOFT_MAX = 0.75
  PROJECTED_FILL_HARD_MAX = 0.95

  enum :state, STATE_VALUES, prefix: :state
  enum :scan, SCAN_VALUES, prefix: :scan

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
  def self.pick_by_node(node, role: nil, required_diskspace: nil)
    q = candidate_query(node, role:)

    if required_diskspace.nil?
      return q
             .group('pools.id')
             .order(Arel.sql('COUNT(dataset_in_pools.id) / pools.max_datasets ASC'))
             .to_a
    end

    candidates = q
                 .select('pools.*, COUNT(dataset_in_pools.id) AS datasets_count')
                 .group('pools.id')
                 .to_a
    fresh_candidates = candidates.select(&:allocation_metrics_fresh?)

    return candidates.sort_by(&:dataset_pressure) if fresh_candidates.empty?

    eligible = fresh_candidates
               .select(&:allocation_state_eligible?)
               .select do |pool|
                 pool.total_space.to_i > 0 &&
                   pool.available_space >= required_diskspace &&
                   pool.projected_fill(required_diskspace) < PROJECTED_FILL_HARD_MAX
               end
    preferred = eligible.select do |pool|
      pool.projected_fill(required_diskspace) < PROJECTED_FILL_SOFT_MAX
    end

    rank_by_live_metrics(preferred.any? ? preferred : eligible, required_diskspace)
  end

  # @param node [::Node]
  # @param role [:hypervisor, :primary]
  # @return [::Pool]
  def self.take_by_node!(node, role: nil, required_diskspace: nil)
    pool, = pick_by_node(node, role:, required_diskspace:)

    if pool.nil?
      if required_diskspace
        raise "no suitable pool available on #{node.domain_name} for #{required_diskspace} MiB"
      end

      raise "no pool available on #{node.domain_name}"
    end

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

  def allocation_metrics_present?
    !total_space.nil? && !used_space.nil? && !available_space.nil?
  end

  def allocation_metrics_fresh?
    return false unless allocation_metrics_present? && checked_at

    (Time.now.utc.to_i - checked_at.to_i) <= ALLOCATION_STATUS_MAX_AGE
  end

  def allocation_state_eligible?
    state_online? || state_degraded?
  end

  def dataset_pressure
    self[:datasets_count].to_f / max_datasets
  end

  def projected_fill(required_diskspace)
    (used_space + required_diskspace).to_f / total_space
  end

  def self.candidate_query(node, role: nil)
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
  end

  def self.rank_by_live_metrics(pools, required_diskspace)
    pools.sort_by do |pool|
      [
        pool.state_online? ? 0 : 1,
        pool.projected_fill(required_diskspace),
        -(pool.available_space - required_diskspace),
        pool.dataset_pressure
      ]
    end
  end

  private_class_method :candidate_query
  private_class_method :rank_by_live_metrics
end
