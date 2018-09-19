module Transactions::Storage
  class CreateDataset < ::Transaction
    t_name :storage_create_dataset
    t_type 5201
    queue :storage

    include Transactions::Utils::UserNamespaces

    def params(dataset_in_pool, opts = nil)
      self.node_id = dataset_in_pool.pool.node_id

      options = opts || {}

      if dataset_in_pool.user_namespace_map
        userns_map = dataset_in_pool.user_namespace_map

        options[:uidmap] = build_map(userns_map, :uid).join(',')
        options[:gidmap] = build_map(userns_map, :gid).join(',')
      end

      options[:canmount] = 'noauto' if dataset_in_pool.pool.node.vpsadminos?

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name,
        options: options.any? ? options : nil,
        create_private: %w(hypervisor primary).include?(dataset_in_pool.pool.role),
      }
    end
  end
end
