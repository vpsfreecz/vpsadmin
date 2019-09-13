module NodeCtld
  class Commands::Dataset::ActivateSnapshotClone < Commands::Base
    handle 5226
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_clone(@pool_fs, @clone_name)
      zfs(:set, 'canmount=on', clone)
      zfs(:mount, nil, clone, valid_rcs: [1])
      zfs(:inherit, 'sharenfs', clone)
    end

    def rollback
      clone = pool_mounted_clone(@pool_fs, @clone_name)
      zfs(:set, 'sharenfs=off', clone)
    end
  end
end
