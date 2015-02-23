module TransactionChains
  class Dataset::Send < ::TransactionChain
    label 'Send snapshots'

    def link_chain(port, src, dst, snapshots, branch, initial = false)
      if initial
        append(
            Transactions::Storage::Recv,
            args: [port, dst, [snapshots.first], branch]
        )
        append(
            Transactions::Storage::Send,
            args: [port, src, [snapshots.first], branch]
        )
        append(
            Transactions::Storage::RecvCheck,
            args: [dst, [snapshots.first], branch],
            &confirm_block([snapshots.first], dst, branch)
        )
      end

      if (initial && snapshots.size > 1) || !initial
        append(
            Transactions::Storage::Recv,
            args: [port, dst, snapshots, branch]
        )
        append(
            Transactions::Storage::Send,
            args: [port, src, snapshots, branch]
        )
        append(
            Transactions::Storage::RecvCheck,
            args: [dst, snapshots, branch],
            &confirm_block(snapshots[1..-1], dst, branch)
        )
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