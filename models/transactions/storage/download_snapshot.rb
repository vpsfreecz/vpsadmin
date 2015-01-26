module Transactions::Storage
  class DownloadSnapshot < ::Transaction
    t_name :storage_download_snapshot
    t_type 5004

    def params(dl, snapshot_in_pool)
      self.t_server = dl.pool.node_id

      {
          pool_fs: dl.pool.filesystem,
          dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
          snapshot: snapshot_in_pool.snapshot.name,
          secret_key: dl.secret_key,
          file_name: dl.file_name
      }
    end
  end
end
