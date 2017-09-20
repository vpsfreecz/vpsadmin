module VpsAdmind
  class Commands::Dataset::CloneSnapshot < Commands::Base
    handle 5217
    needs :system, :zfs, :pool

    def exec
      zfs(
          :clone,
          nil,
          "#{ds} #{pool_mounted_snapshot(@pool_fs, @snapshot_id)}"
      )
    end

    def rollback
      zfs(:destroy, nil, pool_mounted_snapshot(@pool_fs, @snapshot_id), [1])
    end

    protected
    def ds
      if @branch
        "#{@pool_fs}/#{@dataset_name}/#{@dataset_tree}/#{@branch}@#{@snapshot}"
      else
        "#{@pool_fs}/#{@dataset_name}@#{@snapshot}"
      end
    end
  end
end
