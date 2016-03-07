module Transactions::Storage
  class DownloadSnapshot < ::Transaction
    t_name :storage_download_snapshot
    t_type 5004

    def params(dl)
      self.t_server = dl.pool.node_id

      ret = {
          pool_fs: dl.pool.filesystem,
          dataset_name: dl.snapshot.dataset.full_name,
          snapshot: dl.snapshot.name,
          secret_key: dl.secret_key,
          file_name: dl.file_name,
          format: dl.format,
          download_id: dl.id,
      }

      ret[:from_snapshot] = dl.from_snapshot.name if dl.from_snapshot

      if dl.pool.role == 'backup'
        in_branch = ::SnapshotInPoolInBranch.joins(
            snapshot_in_pool: [:dataset_in_pool]
        ).find_by!(
            dataset_in_pools: {pool_id: dl.pool_id},
            snapshot_in_pools: {snapshot_id: dl.snapshot_id},
        )

        ret[:tree] = in_branch.branch.dataset_tree.full_name
        ret[:branch] = in_branch.branch.full_name
      end

      ret
    end
  end
end
