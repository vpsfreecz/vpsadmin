module NodeCtld
  class Commands::Dataset::ApplyRollback < Commands::Base
    handle 5211

    include Utils::System
    include Utils::Zfs

    def exec
      origin = "#{@pool_fs}/#{@dataset_name}"

      begin
        zfs(:umount, nil, origin)

      rescue SystemCommandFailed => e
        raise if e.rc != 1 || e.output !~ /not currently mounted/
      end

      # Move subdatasets from original dataset to the rollbacked one
      children = []
      descendants = []

      # Sort direct children and descendants
      @descendant_datasets.each do |ds|
        ds['relative_name'] = ds['full_name'].sub("#{@dataset_name}/", '')
        puts "Relative: #{ds['full_name']} => #{ds['relative_name']}"

        ds_state = dataset_properties("#{@pool_fs}/#{ds['full_name']}", [:canmount])

        if /\// =~ ds['relative_name']
          descendants << [ds, ds_state]
        else
          children << [ds, ds_state]
        end
      end

      # Disable mount for all descendants
      @descendant_datasets.reverse.each do |ds, ds_state|
        zfs(:set, 'canmount=off', "#{origin}/#{ds['relative_name']}")
      end

      # Rename direct children
      children.each do |child, ds_state|
        zfs(
          :rename,
          nil,
          "#{origin}/#{child['relative_name']} #{origin}.rollback/#{child['relative_name']}"
        )
      end

      # Save original properties
      state = dataset_properties(origin, [
        :atime, :compression, :mountpoint, :quota,
        :recordsize, :refquota, :sync, :canmount,
        :uidmap, :gidmap,
      ])

      # Destroy the original dataset
      zfs(:destroy, '-r', origin)

      # Move the rollbacked one in its place
      zfs(:rename, nil, "#{origin}.rollback #{origin}")

      # Restore original properties
      state.apply_to(origin)

      # Restore and mount all datasets
      zfs(:mount, nil, origin)

      children.each do |ds, ds_state|
        ds_state.apply_to("#{origin}/#{ds['relative_name']}")
        zfs(:mount, nil, "#{origin}/#{ds['relative_name']}")
      end

      descendants.each do |ds, ds_state|
        ds_state.apply_to("#{origin}/#{ds['relative_name']}")
        zfs(:mount, nil, "#{origin}/#{ds['relative_name']}")
      end

      zfs(:share, '-a', '')

      ok
    end
  end
end
