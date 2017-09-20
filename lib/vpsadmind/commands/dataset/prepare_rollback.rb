module VpsAdmind
  class Commands::Dataset::PrepareRollback < Commands::Base
    handle 5209

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:create, '-o canmount=noauto', "#{@pool_fs}/#{@dataset_name}.rollback")
    end

    def rollback
      zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}.rollback")
    end
  end
end
