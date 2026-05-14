module Transactions::Storage
  class DownloadSnapshot < ::Transaction
    t_name :storage_download_snapshot
    t_type 5004

    def params(dl)
      self.node_id = dl.pool.node_id

      ret = {
        pool_fs: dl.pool.filesystem,
        dataset_name: dl.snapshot.dataset.full_name,
        snapshot: dl.snapshot.name,
        secret_key: dl.secret_key,
        file_name: dl.file_name,
        format: dl.format,
        download_id: dl.id
      }

      ret[:from_snapshot] = dl.from_snapshot.name if dl.from_snapshot

      if dl.pool.role == 'backup'
        dataset_in_pool = ::DatasetInPool.find_by!(
          dataset: dl.snapshot.dataset,
          pool_id: dl.pool_id
        )

        in_branch =
          if dl.from_snapshot
            _base, target = ::SnapshotInPoolInBranch.find_pair_for_incremental!(
              dataset_in_pool:,
              snapshot: dl.snapshot,
              from_snapshot: dl.from_snapshot
            )
            target

          else
            ::SnapshotInPoolInBranch.find_for_snapshot!(
              dataset_in_pool:,
              snapshot: dl.snapshot
            )
          end

        ret[:tree] = in_branch.branch.dataset_tree.full_name
        ret[:branch] = in_branch.branch.full_name
      end

      ret
    end
  end
end
