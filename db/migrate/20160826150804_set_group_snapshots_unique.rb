class SetGroupSnapshotsUnique < ActiveRecord::Migration
  def change
    add_index :group_snapshots, %i(dataset_action_id dataset_in_pool_id), unique: true,
              name: :group_snapshots_unique
  end
end
