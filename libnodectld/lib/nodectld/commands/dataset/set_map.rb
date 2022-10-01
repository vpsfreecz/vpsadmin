module NodeCtld
  class Commands::Dataset::SetMap < Commands::Base
    handle 5225

    include Utils::System
    include Utils::Zfs

    def exec
      set_map('new')
      ok
    end

    def rollback
      set_map('original')
      ok
    end

    protected
    def set_map(map_type)
      sorted = @datasets.sort { |a, b| a['name'] <=> b['name'] }

      # Unmount all datasets and set mapping
      sorted.reverse_each do |ds|
        zfs(:set, 'sharenfs=off', ds_name(ds))
        zfs(:umount, nil, ds_name(ds), valid_rcs: [1])

        map = ds[map_type]

        if map.nil?
          zfs(:set, "uidmap=none", ds_name(ds))
          zfs(:set, "gidmap=none", ds_name(ds))
        else
          zfs(:set, "uidmap=\"#{map['uidmap']}\"", ds_name(ds))
          zfs(:set, "gidmap=\"#{map['gidmap']}\"", ds_name(ds))
        end
      end

      # Remount datasets
      sorted.each do |ds|
        zfs(:mount, nil, ds_name(ds))
        zfs(:inherit, 'sharenfs', ds_name(ds))
      end
    end

    def ds_name(ds)
      File.join(ds['pool_fs'], ds['name'])
    end
  end
end
