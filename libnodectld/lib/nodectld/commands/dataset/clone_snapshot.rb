module NodeCtld
  class Commands::Dataset::CloneSnapshot < Commands::Base
    handle 5217
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_clone(@pool_fs, @clone_name)

      zfs(:clone, "-o readonly=on", "#{ds} #{clone}")

      if @uidmap && @gidmap
        zfs(:umount, nil, clone)
        zfs(:set, "uidmap=\"#{@uidmap.join(',')}\" gidmap=\"#{@gidmap.join(',')}\"", clone)
        zfs(:mount, nil, clone)
      end

      zfs(:share, nil, clone)

      ok
    end

    def rollback
      zfs(:destroy, nil, pool_mounted_clone(@pool_fs, @clone_name), valid_rcs: [1])
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
