class AddSnapshotInPoolClones < ActiveRecord::Migration
  class Mount < ActiveRecord::Base ; end
  class SnapshotInPool < ActiveRecord::Base ; end
  class SnapshotInPoolClone < ActiveRecord::Base ; end
  class Vps < ActiveRecord::Base ; end
  class DatasetInPool < ActiveRecord::Base ; end

  def up
    create_table :snapshot_in_pool_clones do |t|
      t.references  :snapshot_in_pool,           null: false
      t.integer     :state,                      null: false, default: 0
      t.string      :name,                       null: false, limit: 50
      t.references  :user_namespace_map,         null: true
      t.integer     :confirmed,                  null: false, default: 0
      t.timestamps
    end

    add_index :snapshot_in_pool_clones, :snapshot_in_pool_id
    add_index :snapshot_in_pool_clones,
      %i(snapshot_in_pool_id user_namespace_map_id),
      unique: true,
      name: 'snapshot_in_pool_clones_unique'

    add_column :mounts, :snapshot_in_pool_clone_id, :integer, null: true
    add_index :mounts, :snapshot_in_pool_clone_id

    ActiveRecord::Base.transaction do
      Mount.where.not(snapshot_in_pool_id: nil).each do |mnt|
        sip = SnapshotInPool.find_by(id: mnt.snapshot_in_pool_id)
        if sip.nil?
          warn "mount ##{mnt.id}: snapshot_in_pool ##{mnt.snapshot_in_pool_id} not found"
          next
        end

        vps = Vps.find_by(id: mnt.vps_id)
        if vps.nil?
          warn "mount ##{mnt.id}: vps ##{mnt.vps_id} not found"
          next
        end

        dip = DatasetInPool.find_by(id: vps.dataset_in_pool_id)
        if dip.nil?
          warn "mount ##{mnt.id}: dataset in pool ##{vps.dataset_in_pool_id} not found"
          next
        end

        cl = SnapshotInPoolClone.create!(
          snapshot_in_pool_id: mnt.snapshot_in_pool_id,
          state: 0,
          name: "#{sip.snapshot_id}.snapshot",
          user_namespace_map_id: dip.user_namespace_map_id,
          confirmed: 1,
          created_at: mnt.created_at,
          updated_at: mnt.updated_at,
        )

        mnt.update!(snapshot_in_pool_clone_id: cl.id)
      end
    end
  end

  def down
    remove_column :mounts, :snapshot_in_pool_clone_id
    drop_table :snapshot_in_pool_clones
  end
end
