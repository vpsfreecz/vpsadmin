module Transactions::Storage
  class CreateDataset < ::Transaction
    t_name :storage_create_dataset
    t_type 5201
    queue :storage

    def params(dataset_in_pool, opts = nil)
      self.node_id = dataset_in_pool.pool.node_id

      options = opts || {}

      if dataset_in_pool.user_namespace
        opts[:uidoffset] = dataset_in_pool.user_namespace.offset
        opts[:gidoffset] = dataset_in_pool.user_namespace.offset
      end

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name,
        options: options.any? ? options : nil,
        create_private: %w(hypervisor primary).include?(dataset_in_pool.pool.role),
      }
    end
  end
end
