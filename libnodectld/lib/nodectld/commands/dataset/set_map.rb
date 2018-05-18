module NodeCtld
  class Commands::Dataset::SetMap < Commands::Base
    handle 5225

    include Utils::System
    include Utils::Zfs

    def exec
      set_map(@new)
      ok
    end

    def rollback
      set_map(@original)
      ok
    end

    protected
    def set_map(map)
      zfs(:set, 'sharenfs=off', ds)
      zfs(:umount, nil, ds, valid_rcs: [1])

      if map.nil?
        zfs(:set, "uidmap=none", ds)
        zfs(:set, "gidmap=none", ds)
      else
        zfs(:set, "uidmap=\"#{map['uidmap']}\"", ds)
        zfs(:set, "gidmap=\"#{map['gidmap']}\"", ds)
      end

      zfs(:mount, nil, ds)
      zfs(:inherit, 'sharenfs', ds)
    end

    def ds
      File.join(@pool_fs, @name)
    end
  end
end
