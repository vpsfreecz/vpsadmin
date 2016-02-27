module Transactions::Storage
  class DownloadSnapshot < ::Transaction
    t_name :storage_download_snapshot
    t_type 5004

    def params(dl, snapshot_in_pool, format)
      self.t_server = dl.pool.node_id

      ret = {
          pool_fs: dl.pool.filesystem,
          dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
          snapshot: snapshot_in_pool.snapshot.name,
          secret_key: dl.secret_key,
          file_name: dl.file_name,
          format: format,
          download_id: dl.id,
      }

      if snapshot_in_pool.dataset_in_pool.pool.role == 'backup'
        in_branch = ::SnapshotInPoolInBranch.joins(branch: [:dataset_tree]).find_by!(
            dataset_trees: {dataset_in_pool_id: snapshot_in_pool.dataset_in_pool_id},
            snapshot_in_pool_id: snapshot_in_pool.id
        )

        ret[:tree] = in_branch.branch.dataset_tree.full_name
        ret[:branch] = in_branch.branch.full_name
      end

      ret
    end
  end
end
