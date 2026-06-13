module NodeCtld
  class Commands::Dataset::Rename < Commands::Base
    handle 5230

    include Utils::System
    include Utils::Zfs

    def exec
      zfs(:rename, '-p', "#{@pool_fs}/#{@old_name} #{@pool_fs}/#{@new_name}")
      ok
    end

    def rollback
      zfs(:rename, '-p', "#{@pool_fs}/#{@new_name} #{@pool_fs}/#{@old_name}", valid_rcs: [1])
      ok
    end
  end
end
