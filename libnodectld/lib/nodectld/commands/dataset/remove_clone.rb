module NodeCtld
  class Commands::Dataset::RemoveClone < Commands::Base
    handle 5218
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_clone(@pool_fs, @snapshot_id)

      zfs(:set, 'sharenfs=off', clone)
      zfs(:destroy, nil, clone)
    end

    def rollback
      clone = pool_mounted_clone(@pool_fs, @snapshot_id)

      # the dataset might exist if destroy failed
      zfs(:clone, "-o readonly=on", "#{ds} #{clone}", valid_rcs: [1])

      if @uidmap && @gidmap
        zfs(:umount, nil, clone)
        zfs(:set, "uidmap=\"#{@uidmap.join(',')}\" gidmap=\"#{@gidmap.join(',')}\"", clone)
        zfs(:mount, nil, clone)
      end

      zfs(:inherit, 'sharenfs', clone)
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
