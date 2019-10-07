module Transactions::Export
  class Disable < ::Transaction
    t_name :export_disable
    t_type 5404
    queue :storage

    def params(export)
      self.node_id = export.dataset_in_pool.pool.node_id

      {
        export_id: export.id,
      }
    end
  end
end
