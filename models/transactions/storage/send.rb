module Transactions::Storage
  class Send < ::Transaction
    t_name :storage_send
    t_type 5221
    queue :zfs_send

    def params(port, src, snapshots, branch = nil)
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
          addr: port.addr,
          port: port.port,
          src_pool_fs: src.pool.filesystem,
          dataset_name: src.dataset.full_name,
          snapshots: tmp,
          tree: branch && branch.dataset_tree.full_name,
          branch: branch && branch.full_name
      }
    end
  end
end
