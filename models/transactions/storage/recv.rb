module Transactions::Storage
  class Recv < ::Transaction
    t_name :storage_recv
    t_type 5220

    def params(port, dst, snapshots, branch = nil, ds_suffix = nil)
      self.t_server = dst.pool.node_id

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
          dst_pool_fs: dst.pool.filesystem,
          dataset_name: ds_suffix ? "#{dst.dataset.full_name}.#{ds_suffix}" : dst.dataset.full_name,
          snapshots: tmp,
          tree: branch && branch.dataset_tree.full_name,
          branch: branch && branch.full_name
      }
    end
  end
end
