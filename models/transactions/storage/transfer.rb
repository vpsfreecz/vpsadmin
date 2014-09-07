module Transactions::Storage
  class Transfer < ::Transaction
    t_name :storage_transfer
    t_type 5205

    def params(src, dst, snapshots, branch = nil, initial = false)
      self.t_server = dst.pool.node_id

      tmp = []

      snapshots.each do |snap|
        tmp << {
            id: snap.id,
            name: snap.snapshot.name,
            confirmed: snap.snapshot.confirmed
        }
      end

      {
          src_node_addr: src.pool.node.addr,
          src_pool_fs: src.pool.filesystem,
          dst_pool_fst: dst.pool.filesystem,
          dataset_name: src.dataset.full_name,
          snapshots: tmp,
          initial: initial,
          branch: branch.name
      }
    end
  end
end
