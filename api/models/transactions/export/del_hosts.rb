module Transactions::Export
  class DelHosts < ::Transaction
    t_name :export_del_hosts
    t_type 5406
    queue :storage

    def params(export, ip_addresses)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
        pool_fs: export.dataset_in_pool.pool.filesystem,
        dataset_name: export.dataset_in_pool.dataset.full_name,
        snapshot_clone: export.snapshot_in_pool_clone && export.snapshot_in_pool_clone.name,
        as: export.path,
        hosts: ip_addresses.map do |ip|
          {
            address: ip.to_s,
            options: {
              rw: export.rw,
              sync: export.sync,
              subtree_check: export.subtree_check,
              root_squash: export.root_squash,
            },
          }
        end,
      }
    end
  end
end
