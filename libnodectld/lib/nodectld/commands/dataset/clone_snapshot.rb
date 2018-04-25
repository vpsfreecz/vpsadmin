module NodeCtld
  class Commands::Dataset::CloneSnapshot < Commands::Base
    handle 5217
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_snapshot(@pool_fs, @snapshot_id)

      zfs(:clone, "-o readonly=on", "#{ds} #{clone}")

      if @uidoffset && @gidoffset
        zfs(:umount, nil, clone)
        zfs(:set, "uidoffset=#{@uidoffset} gidoffset=#{@gidoffset}", clone)
        zfs(:mount, nil, clone)
      end

      ok
    end

    def rollback
      zfs(:destroy, nil, pool_mounted_snapshot(@pool_fs, @snapshot_id), valid_rcs: [1])
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
