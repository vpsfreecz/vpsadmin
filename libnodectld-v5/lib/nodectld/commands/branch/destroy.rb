module NodeCtld
  class Commands::Branch::Destroy < Commands::Base
    handle 5207

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@branch}")
    end
  end
end
