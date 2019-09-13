module VpsAdmind
  class Commands::Dataset::DeactivateSnapshotClone < Commands::Base
    handle 5227
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_snapshot(@pool_fs, @clone_name)
      zfs(:set, 'sharenfs=off', clone)
    end

    def rollback
      clone = pool_mounted_snapshot(@pool_fs, @clone_name)
      zfs(:inherit, 'sharenfs', clone)
    end
  end
end
