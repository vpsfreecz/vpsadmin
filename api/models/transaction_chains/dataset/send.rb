module TransactionChains
  class Dataset::Send < ::TransactionChain
    label 'Send'

    def link_chain(port, src, dst, snapshots, src_branch, dst_branch, initial = false, ds_suffix = nil, **opts)
      if opts[:send_reservation]
        append(Transactions::Queue::Reserve, args: [src.pool.node, :zfs_send])
        append(Transactions::Queue::Reserve, args: [dst.pool.node, :zfs_recv])
      end

      if initial
        if local_send?(src, dst)
          append(
            Transactions::Storage::LocalSend,
            args: [src, dst, [snapshots.first], src_branch, dst_branch, ds_suffix],
            &confirm_block([snapshots.first], dst, dst_branch)
          )

        else
          append(
            Transactions::Storage::Recv,
            args: [port, dst, [snapshots.first], dst_branch, ds_suffix]
          )
          append(
            Transactions::Storage::Send,
            args: [port, src, [snapshots.first], src_branch]
          )
          append(
            Transactions::Storage::RecvCheck,
            args: [dst, [snapshots.first], dst_branch, ds_suffix],
            &confirm_block([snapshots.first], dst, dst_branch)
          )
        end
      end

      if (initial && snapshots.size > 1) || !initial
        if local_send?(src, dst)
          append(
            Transactions::Storage::LocalSend,
            args: [src, dst, snapshots, src_branch, dst_branch, ds_suffix],
            &confirm_block(snapshots[1..], dst, dst_branch)
          )

        else
          append(
            Transactions::Storage::Recv,
            args: [port, dst, snapshots, dst_branch, ds_suffix]
          )
          append(
            Transactions::Storage::Send,
            args: [port, src, snapshots, src_branch]
          )
          append(
            Transactions::Storage::RecvCheck,
            args: [dst, snapshots, dst_branch, ds_suffix],
            &confirm_block(snapshots[1..], dst, dst_branch)
          )
        end
      end

      return unless opts[:send_reservation]

      append(Transactions::Queue::Release, args: [dst.pool.node, :zfs_recv])
      append(Transactions::Queue::Release, args: [src.pool.node, :zfs_send])
    end

    protected

    def local_send?(src, dst)
      src.pool.node_id == dst.pool.node_id
    end

    def confirm_block(snapshots, dst, branch)
      # After rollback, a previously promoted-away branch can become the head
      # again while still being a ZFS clone. Rollback records that clone origin
      # on the branch entries newer than the origin snapshot; appended snapshots
      # must keep depending on the same origin.
      branch_parent = branch && branch_parent_entry(branch)

      proc do
        snapshots.each do |snap|
          # A backup tree can reference snapshots that are already mirrored in
          # the same destination dataset through another branch or tree.
          sip = ::SnapshotInPool.find_by(
            snapshot_id: snap.snapshot_id,
            dataset_in_pool: dst
          )

          unless sip
            sip = ::SnapshotInPool.create!(
              snapshot_id: snap.snapshot_id,
              dataset_in_pool: dst,
              confirmed: ::SnapshotInPool.confirmed(:confirm_create)
            )

            create(sip)
          end

          next unless dst.pool.role == 'backup'

          entry = ::SnapshotInPoolInBranch.find_by(snapshot_in_pool: sip, branch: branch)
          next if entry

          create(::SnapshotInPoolInBranch.create!(
                   snapshot_in_pool: sip,
                   branch:,
                   snapshot_in_pool_in_branch: branch_parent,
                   confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_create)
                 ))
          increment(branch_parent.snapshot_in_pool, :reference_count) if branch_parent
        end
      end
    end

    def branch_parent_entry(branch)
      ::SnapshotInPoolInBranch.live
                              .includes(:snapshot_in_pool_in_branch)
                              .joins(:snapshot_in_pool)
                              .where(branch:)
                              .where.not(snapshot_in_pool_in_branch_id: nil)
                              .order('snapshot_in_pools.snapshot_id DESC')
                              .take
                              &.snapshot_in_pool_in_branch
    end
  end
end
