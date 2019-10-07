module Transactions::Export
  class Enable < ::Transaction
    t_name :export_enable
    t_type 5403
    queue :storage

    def params(export)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
      }
    end
  end
end
