module Transactions::Storage
  class LocalSend < ::Transaction
    t_name :storage_local_send
    t_type 5223

    def params(src, dst, snapshots, src_branch = nil, dst_branch = nil)
      self.t_server = src.pool.node_id

      tmp = []

      snapshots.each do |snap|
        tmp << {
            id: snap.snapshot.id,
            name: snap.snapshot.name,
            confirmed: snap.snapshot.confirmed
        }
      end

      {
          src_pool_fs: src.pool.filesystem,
          dst_pool_fs: dst.pool.filesystem,
          src_dataset_name: src.dataset.full_name,
          dst_dataset_name: dst.dataset.full_name,
          snapshots: tmp,
          src_tree: src_branch && src_branch.dataset_tree.full_name,
          src_branch: src_branch && src_branch.full_name,
          dst_tree: dst_branch && dst_branch.dataset_tree.full_name,
          dst_branch: dst_branch && dst_branch.full_name
      }
    end
  end
end
