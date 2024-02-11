module Transactions::Storage
  class RsyncDataset < ::Transaction
    t_name :storage_rsync_dataset
    t_type 5229
    queue :zfs_send

    def params(src, dst, allow_partial: false)
      self.node_id = dst.pool.node_id

      {
        src_addr: src.pool.node.ip_addr,
        src_pool_fs: src.pool.filesystem,
        dst_pool_name: dst.pool.name,
        dst_pool_fs: dst.pool.filesystem,
        dataset_name: src.dataset.full_name,
        allow_partial:
      }
    end
  end
end
