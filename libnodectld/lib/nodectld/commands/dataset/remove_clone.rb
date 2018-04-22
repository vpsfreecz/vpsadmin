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
        "#{ds} #{pool_mounted_snapshot(@pool_fs, @snapshot_id)}"
      )
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
