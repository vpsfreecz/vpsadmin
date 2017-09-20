module VpsAdmind
  class Commands::DatasetTree::Destroy < Commands::Base
    handle 5214

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}/#{@tree}")
    end
  end
end
