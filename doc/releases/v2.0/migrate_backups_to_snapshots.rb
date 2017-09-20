#!/usr/bin/env ruby
Dir.chdir('/opt/vpsadminapi')
$:.insert(0, '/opt/haveapi/lib')
require '/opt/vpsadminapi/lib/vpsadmin'

# ID of backup pool on which the backups are stored
BACKUP_POOL = 14

class VpsBackup < ActiveRecord::Base
  belongs_to :vps
end

Vps.transaction do
  Vps.includes(dataset_in_pool: [:dataset]).all.each do |vps|
    q = VpsBackup.where(vps: vps).order('`timestamp`')
    next if q.empty?

    oldest_backup = q.take

    next if oldest_backup.nil?

    t = Time.at(oldest_backup.timestamp)

    # Find backup dataset in pool
    backup_dip = vps.dataset_in_pool.dataset.dataset_in_pools.where(
        pool_id: BACKUP_POOL
    ).take!

    # Create dataset tree
    tree = DatasetTree.create!(
        dataset_in_pool: backup_dip,
        head: false,
        confirmed: DatasetTree.confirmed(:confirmed),
        created_at: t
    )

    # Create a branch
    branch = Branch.create!(
        dataset_tree: tree,
        name: t.strftime('%Y-%m-%dT%H:%M:%S'),
        head: false,
        confirmed: Branch.confirmed(:confirmed),
        created_at: t
    )

    q.each do |backup|
      t = Time.at(backup.timestamp)
      t_str = t.strftime('%Y-%m-%dT%H:%M:%S')

      # Create snapshot in pool and snapshot in branch for all backups
      s = Snapshot.create!(
          dataset: vps.dataset_in_pool.dataset,
          name: t_str,
          confirmed: Snapshot.confirmed(:confirmed),
          created_at: t
      )

      sip = SnapshotInPool.create!(
          snapshot: s,
          dataset_in_pool: backup_dip,
          confirmed: SnapshotInPool.confirmed(:confirmed)
      )

      SnapshotInPoolInBranch.create!(
          snapshot_in_pool: sip,
          branch: branch,
          confirmed: SnapshotInPoolInBranch.confirmed(:confirmed)
      )
    end
  end
end

