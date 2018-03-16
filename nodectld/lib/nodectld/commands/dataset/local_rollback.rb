module NodeCtld
  class Commands::Dataset::LocalRollback < Commands::Base
    handle 5208

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:rollback, '-r', "#{@pool_fs}/#{@dataset_name}@#{@snapshot}")
    end
  end
end
