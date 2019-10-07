module Transactions::Export
  class Destroy < ::Transaction
    t_name :export_destroy
    t_type 5402
    queue :storage

    def params(export, host_addr)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
        address: host_addr.ip_addr,
      }
    end
  end
end
