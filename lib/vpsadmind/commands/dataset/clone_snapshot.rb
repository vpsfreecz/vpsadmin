module VpsAdmind
  class Commands::Dataset::CloneSnapshot < Commands::Base
    handle 5217
    needs :system, :zfs, :pool

    def exec
      zfs(
          :clone,
          nil,
          "#{@pool_fs}/#{@dataset_name}@#{@snapshot} #{pool_mounted_snapshot(@pool_fs, @snapshot_id)}"
      )
    end

    def rollback
      zfs(:destroy, nil, pool_mounted_snapshot(@pool_fs, @snapshot_id), [1])
    end
  end
end
