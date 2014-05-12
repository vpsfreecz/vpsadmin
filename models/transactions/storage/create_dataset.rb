module Transactions::Storage
  class CreateDataset < ::Transaction
    t_name :storage_create_dataset
    t_type 5201

    def params(export)
      self.t_server = export.storage_root.node.id

      {
          dataset: export.dataset,
          path: export.path,
          quota: export.quota,
          export_id: export.id,
      }
    end
  end
end
