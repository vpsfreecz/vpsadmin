class AddSnapshotHistoryIdentifier < ActiveRecord::Migration
  class Dataset < ActiveRecord::Base
    has_many :dataset_in_pools
    has_many :snapshots
  end

  class DatasetInPool < ActiveRecord::Base
    belongs_to :dataset
    has_many :dataset_trees
  end

  class DatasetTree < ActiveRecord::Base
    belongs_to :dataset_in_pool
    has_many :branches
  end

  class Branch < ActiveRecord::Base
    belongs_to :dataset_tree
    has_many :snapshot_in_pool_in_branches
  end

  class Snapshot < ActiveRecord::Base
    belongs_to :dataset
    has_many :snapshot_in_pools
  end

  class SnapshotInPool < ActiveRecord::Base
    belongs_to :snapshot
    belongs_to :dataset_in_pool
  end

  class SnapshotInPoolInBranch < ActiveRecord::Base
    belongs_to :snapshot_in_pool
    belongs_to :branch
  end

  def change
    add_column :datasets, :current_history_id, :integer, null: false, default: 0
    add_column :snapshots, :history_id, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        Dataset.all.includes(:dataset_in_pools, :snapshots).each do |ds|
          handle_dataset(ds)
        end
      end
    end
  end

  protected
  def handle_dataset(ds)
    head = nil
    history_id = nil
    snapshots = {}

    # Walk through all branches
    Branch.includes(
        :dataset_tree
    ).joins(
        dataset_tree: [:dataset_in_pool]
    ).where(
        dataset_in_pools: {dataset_id: ds.id}
    ).order('branches.created_at, branches.id').each do |branch|
        
      history_id ||= 0
      head = history_id if branch.head && branch.dataset_tree.head

      branch.snapshot_in_pool_in_branches.includes(
          snapshot_in_pool: [:snapshot]
      ).each do |sipb|
        snapshots[ sipb.snapshot_in_pool.snapshot ] ||= history_id
      end

      history_id += 1

    end

    # Walk through snapshots that do not have backups
    ds.snapshots.order('created_at, id').each do |s|
      next if snapshots.has_key?(s)

      snapshots[s] = head || history_id || 0
    end

    # Save changes
    snapshots.each do |s, h|
      s.update!(history_id: h)
    end

    ds.update(
        current_history_id: (head || history_id || 0)
    )
  end
end
