module Transactions::Export
  class Set < ::Transaction
    t_name :export_set
    t_type 5407
    queue :storage

    def params(old_export, new_export)
      self.node_id = old_export.dataset_in_pool.pool.node_id

      {
        export_id: old_export.id,
        new: {
          threads: new_export.threads,
        },
        original: {
          threads: old_export.threads,
        },
      }
    end
  end
end
