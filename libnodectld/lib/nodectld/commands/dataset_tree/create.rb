module NodeCtld
  class Commands::DatasetTree::Create < Commands::Base
    handle 5213

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:create, "-o canmount=noauto", tree_name)
    end

    def rollback
      zfs(:destroy, nil, tree_name)
    end

    protected
    def tree_name
      "#{@pool_fs}/#{@dataset_name}/#{@tree}"
    end
  end
end
