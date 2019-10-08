module Transactions::Export
  class AddHosts < ::Transaction
    t_name :export_add_hosts
    t_type 5405
    queue :storage

    def params(export, hosts)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
        pool_fs: export.dataset_in_pool.pool.filesystem,
        dataset_name: export.dataset_in_pool.dataset.full_name,
        snapshot_clone: export.snapshot_in_pool_clone && export.snapshot_in_pool_clone.name,
        as: export.path,
        hosts: hosts.map do |h|
          {
            address: h.ip_address.to_s,
            options: {
              rw: h.rw,
              sync: h.sync,
              subtree_check: h.subtree_check,
              root_squash: h.root_squash,
            },
          }
        end,
      }
    end
  end
end
