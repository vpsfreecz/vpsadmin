module NodeCtld
  class Commands::Dataset::RemoveClone < Commands::Base
    handle 5218
    needs :system, :zfs, :pool

    def exec
      zfs(:set, 'sharenfs=off', pool_mounted_snapshot(@pool_fs, @snapshot_id))
      zfs(:destroy, nil, pool_mounted_snapshot(@pool_fs, @snapshot_id))
    end

    def rollback
      zfs(
        :clone,
        "-o readonly=on",
        "#{ds} #{pool_mounted_snapshot(@pool_fs, @snapshot_id)}",
        valid_rcs: [1] # the dataset might exist if destroy failed
      )

      if @uidmap && @gidmap
        zfs(:umount, nil, clone)
        zfs(:set, "uidmap=\"#{@uidmap.join(',')}\" gidmap=\"#{@gidmap.join(',')}\"", clone)
        zfs(:mount, nil, clone)
      end

      zfs(:inherit, 'sharenfs', pool_mounted_snapshot(@pool_fs, @snapshot_id))
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
