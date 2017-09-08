class DatasetInPool < ActiveRecord::Base
  belongs_to :dataset
  belongs_to :pool
  has_many :snapshot_in_pools
  has_many :dataset_trees
  has_many :dataset_properties
  has_many :mounts
  has_many :dataset_in_pool_plans
  has_many :src_dataset_actions, class_name: 'DatasetAction',
           foreign_key: :src_dataset_in_pool_id
  has_many :dst_dataset_actions, class_name: 'DatasetAction',
           foreign_key: :dst_dataset_in_pool_id
  has_many :group_snapshots

  include Lockable
  include Confirmable
  include HaveAPI::Hookable
  include VpsAdmin::API::DatasetProperties::Model
  include VpsAdmin::API::ClusterResources

  cluster_resources required: %i(diskspace),
                    environment: ->(){ pool.node.location.environment }

  has_hook :create,
      desc: 'Called when a new DatasetInPool is being created',
      context: 'TransactionChains::Dataset::Create instance',
      args: {
          dataset_in_pool: 'instance of DatasetInPool'
      }
  has_hook :migrated,
      desc: 'Called when a DatasetInPool is being migrated with a VPS',
      context: 'TransactionChains::Vps::Migrate instance',
      args: {
          src_dataset_in_pool: 'source DatasetInPool',
          dst_dataset_in_pool: 'target DatasetInPool',
      }

  # @param opts [Hash] options
  # @option opts [String] label user-friendly snapshot label
  def snapshot(opts)
    TransactionChains::Dataset::Snapshot.fire(self, opts)
  end

  # +dst+ is destination DatasetInPool.
  def transfer(dst)
    TransactionChains::Dataset::Transfer.fire(self, dst)
  end

  def rollback(snap)
    TransactionChains::Dataset::Rollback.fire(self, snap)
  end

  def backup(dst)
    TransactionChains::Dataset::Backup.fire(self, dst)
  end

  def add_plan(plan)
    VpsAdmin::API::DatasetPlans.plans[plan.dataset_plan.name.to_sym].register(self)
  end

  def del_plan(dip_plan)
    VpsAdmin::API::DatasetPlans.plans[dip_plan.environment_dataset_plan.dataset_plan.name.to_sym].unregister(self)
  end

  def subdatasets_in_pool
    ret = []

    dataset.subtree.arrange.each do |k, v|
      ret.concat(recursive_serialize(k, v))
    end

    ret
  end

  def effective_quota
    dataset.effective_quota
  end

  protected
  def recursive_serialize(dataset, children)
    ret = []

    # First parents
    dip = dataset.dataset_in_pools.where(pool: pool).take

    return ret unless dip

    ret << dip

    # Then children
    children.each do |k, v|
      if v.is_a?(::Dataset)
        dip = v.dataset_in_pools.where(pool: pool).take
        next unless dip

        ret << dip

      else
        ret.concat(recursive_serialize(k, v))
      end
    end

    ret
  end
end
