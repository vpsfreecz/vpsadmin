module NodeCtld
  class Commands::Dataset::RemoveClone < Commands::Base
    handle 5218
    needs :system, :zfs, :pool

    def exec
      clone = pool_mounted_clone(@pool_fs, @clone_name)

      zfs(:set, 'canmount=off', clone)
      zfs(:destroy, nil, clone)
    end
  end
end
