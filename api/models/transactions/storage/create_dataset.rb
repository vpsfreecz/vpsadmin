module Transactions::Storage
  class CreateDataset < ::Transaction
    t_name :storage_create_dataset
    t_type 5201
    queue :storage

    include Transactions::Utils::UserNamespaces

    def params(dataset_in_pool, fs_opts = nil, cmd_opts = {})
      self.node_id = dataset_in_pool.pool.node_id

      options = fs_opts || {}

      if cmd_opts.fetch(:set_map, true) && cmd_opts[:userns_map]
        userns_map = cmd_opts[:userns_map]

        options[:uidmap] = build_map(userns_map, :uid).join(',')
        options[:gidmap] = build_map(userns_map, :gid).join(',')
      end

      if dataset_in_pool.pool.node.vpsadminos? \
         && (dataset_in_pool.pool.hypervisor? || dataset_in_pool.pool.backup?)
        options[:canmount] ||= 'noauto'
      end

      {
        pool_fs: dataset_in_pool.pool.filesystem,
        name: dataset_in_pool.dataset.full_name,
        options: options.any? ? options : nil,
        create_private: create_private?(dataset_in_pool, cmd_opts),
      }
    end

    protected
    def create_private?(dip, cmd_opts)
      if cmd_opts[:create_private].nil?
        %w(hypervisor primary).include?(dip.pool.role)
      else
        cmd_opts[:create_private]
      end
    end
  end
end
