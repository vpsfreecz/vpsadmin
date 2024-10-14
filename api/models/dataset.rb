require 'vpsadmin/api/maintainable'
require 'vpsadmin/api/dataset_properties'
require 'vpsadmin/api/lifetimes'
require_relative 'confirmable'
require_relative 'lockable'
require_relative 'transaction_chains/dataset/destroy'

class Dataset < ApplicationRecord
  belongs_to :user
  belongs_to :dataset_expansion
  has_many :dataset_in_pools
  has_many :snapshots
  has_many :dataset_properties
  has_many :dataset_expansions

  has_ancestry cache_depth: true

  before_save :cache_full_name

  include Confirmable
  include Lockable
  include VpsAdmin::API::Maintainable::Check
  include VpsAdmin::API::DatasetProperties::Model

  include VpsAdmin::API::Lifetimes::Model
  set_object_states states: %i[active deleted],
                    deleted: {
                      enter: TransactionChains::Dataset::Destroy
                    }

  validates :name, format: {
    with: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:.]{0,254}\z/,
    message: "'%{value}' is not a valid dataset name"
  }, exclusion: {
    in: %w[private vpsadmin],
    message: "'%{value}' is a reserved name"
  }
  validate :check_name

  def destroy
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    TransactionChains::DatasetInPool::Destroy.fire(dip, { recursive: true })
  end

  def check_name
    return unless name.present?

    errors.add(:mountpoint, "'..' not allowed in dataset name") if name =~ /\.\./

    %w[branch- tree.].each do |prefix|
      if name.start_with?(prefix)
        errors.add(:name, "cannot start with prefix '#{prefix}'")
        break
      end
    end
  end

  def resolve_full_name
    if parent_id
      "#{parent.resolve_full_name}/#{name}"
    else
      name
    end
  end

  def environment
    dataset_in_pools.each do |dip|
      return dip.pool.node.location.environment if dip.pool.role != 'backup'
    end

    nil
  end

  # Returns DatasetInPool of +self+ on pools with +hypervisor+
  # or +primary+ role.
  def primary_dataset_in_pool!
    dataset_in_pools.joins(:pool).where.not(pools: { role: Pool.roles[:backup] }).take!
  end

  def export
    ::Export.joins(:dataset_in_pool).where(
      dataset_in_pools: { dataset_id: id },
      snapshot_in_pool_clone: nil
    ).take
  end

  # Return the maximum number of snapshots of all dataset in pools
  def max_snapshots
    dataset_in_pools.maximum(:max_snapshots)
  end

  # Since property `quota` can be `none`, i.e. `0`, this method returns
  # quota from the closest parent that has it set.
  def effective_quota
    return quota if quota != 0 || root?

    parent.effective_quota
  end

  protected

  def cache_full_name
    self.full_name = resolve_full_name
  end
end
