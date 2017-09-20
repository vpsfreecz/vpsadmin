module TransactionChains
  class Dataset::Send < ::TransactionChain
    label 'Send'

    def link_chain(port, src, dst, snapshots, src_branch, dst_branch, initial = false, ds_suffix = nil)
      if initial
        if src.pool == dst.pool
          append(
              Transactions::Storage::LocalSend,
              args: [src, dst, [snapshots.first], src_branch, dst_branch],
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
        if src.pool == dst.pool
          append(
              Transactions::Storage::LocalSend,
              args: [src, dst, snapshots, src_branch, dst_branch],
              &confirm_block(snapshots[1..-1], dst, dst_branch)
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
              &confirm_block(snapshots[1..-1], dst, dst_branch)
          )
        end
      end
    end

    protected
    def confirm_block(snapshots, dst, branch)
      Proc.new do
        snapshots.each do |snap|
          sip = ::SnapshotInPool.create(
              snapshot_id: snap.snapshot_id,
              dataset_in_pool: dst,
              confirmed: ::SnapshotInPool.confirmed(:confirm_create)
          )

          create(sip)

          if dst.pool.role == 'backup'
            create(::SnapshotInPoolInBranch.create(
                snapshot_in_pool: sip,
                branch: branch,
                confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_create)
            ))
          end
        end
      end
    end
  end
end