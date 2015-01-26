module Transactions::Storage
  class RemoveDownload < ::Transaction
    t_name :storage_remove_download
    t_type 5005
    irreversible

    def params(dl)
      self.t_server = dl.pool.node_id

      {
          pool_fs: dl.pool.filesystem,
          secret_key: dl.secret_key,
          file_name: dl.file_name
      }
    end
  end
end
