module NodeCtld
  class Commands::Dataset::RemoveClone < Commands::Base
    handle 5218
    needs :system, :zfs, :pool

    def exec
      zfs(:destroy, nil, pool_mounted_snapshot(@pool_fs, @snapshot_id))
    end

    def rollback
      zfs(
          :clone,
          nil,
          "#{@pool_fs}/#{@dataset_name}@#{@snapshot} #{pool_mounted_snapshot(@pool_fs, @snapshot_id)}"
      )
    end
  end
end
