module VpsAdmind
  class Commands::DatasetTree::Create < Commands::Base
    handle 5213

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:create, nil, "#{@pool_fs}/#{@dataset_name}/#{@tree}")
    end
  end
end
