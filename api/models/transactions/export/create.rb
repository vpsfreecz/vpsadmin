module Transactions::Export
  class Create < ::Transaction
    t_name :export_create
    t_type 5401
    queue :storage

    def params(export, host_addr)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
        address: host_addr.ip_addr,
        threads: export.threads,
      }
    end
  end
end
