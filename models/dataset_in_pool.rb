class DatasetInPool < ActiveRecord::Base
  belongs_to :dataset
  belongs_to :pool
  has_many :snapshot_in_pools
  has_many :branches
  has_many :mounts

  include Lockable

  def snapshot
    snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

    s = Snapshot.create(
        name: "#{snap} (unconfirmed)",
        dataset_id: dataset_id,
        confirmed: false
    )

    sip = SnapshotInPool.create(
        snapshot: s,
        dataset_in_pool: self,
        confirmed: false
    )

    Transactions::Storage::CreateSnapshot.fire(sip) do
      create s
      create sip
    end
  end

  # +dst+ is destination DatasetInPool.
  def transfer(dst)
    branch = nil
    last_trans = nil
    dst_last_snapshot = dst.snapshot_in_pools.all.order('snapshot_id DESC').take

    # no snapshots on the destination
    if dst_last_snapshot.nil?
      # send everything
      # - first send the first snapshot from src to dst
      # - then send all snapshots incrementally, if there are any

      transfer_snapshots = snapshot_in_pools.all.join(:snapshots).order('id ASC')

      if transfer_snapshots.empty?
        # no snapshots to transfer
        return
      end

      # destination is branched
      if dst.pool.role == :backup
        # create branch unless it exists
        # mark branch as head
        # put all snapshots inside it

        branch = Branch.find_by(dataset_in_pool: dst, head: true)

        unless branch
          branch = Branch.create(
              dataset_in_pool: dst,
              name: Time.new.strftime('%Y-%m-%dT%H:%M:%S'),
              head: true,
              confirmed: false
          )
        end

        last_trans = Transactions::Storage::CreateDataset.fire(branch) do
          create branch
        end
      end

      Transactions::Storage::Transfer.fire_chained(last_trans, self, dst, transfer_snapshots, branch, true) do
        transfer_snapshots.each do |snap|
          sip = SnapshotInPool.create(
              snapshot_id: snap.snapshot_id,
              dataset_in_pool: dst,
              confirmed: false
          )

          create sip

          if dst.pool.role == :backup
            create SnapshotInPoolInBranch.create(
                snapshot_in_pool: sip,
                branch: branch,
                confirmed: false
            )
          end
        end
      end

    else
      # there are snapshots on the destination

      if dst.pool.role == :backup
        branch = Branch.find_by!(dataset_in_pool: dst, head: true)

        # select last snapshot from head branch
        dst_last_snapshot = branch.snapshot_in_pool_in_branches
          .joins(:snapshot_in_pool)
          .order('snapshot_id DESC').take!.snapshot_in_pool

        # dst_last_snapshot = SnapshotInPool
        #   .select('snapshot_in_pools.*')
        #   .joins(:snapshot_in_pool_in_branches, :branches)
        #   .where('branches.head = 1 AND snapshot_in_pool_in_branches.dataset_in_pool_id = ?', dst.id)
        #   .order('snapshot_id DESC').take
      end

      src_last_snapshot = nil
      transfer_snapshots = []

      # select all snapshots from source in reverse order
      snapshot_in_pools.joins(:snapshots).order('snapshot_id DESC').each do |snap|
        src_last_snapshot ||= snap
        transfer_snapshots.insert(0, snap)

        if dst_last_snapshot.snapshot_id == snap.snapshot_id # found the common snapshot
          # incremental send from snap to src_last_snap
          # if they are the same, it is the last snapshot on source and nothing has to be sent
          unless src_last_snapshot.snapshot_id == snap.snapshot_id
            Transactions::Storage::Transfer.fire(self, dst, transfer_snapshots, branch) do
              transfer_snapshots.each do |s|
                sip = SnapshotInPool.create(
                    snapshot_id: s.snapshot_id,
                    dataset_in_pool: dst,
                    confirmed: false
                )

                create sip

                if dst.pool.role == :backup
                  create SnapshotInPoolInBranch.create(
                      snapshot_in_pool: sip,
                      branch: branch,
                      confirmed: false
                  )
                end
              end
            end

            return
          end
        end
      end

      # FIXME report err
      warn "history does not match, cannot make a transfer"

    end
  end

  def rollback(snap)

  end
end
