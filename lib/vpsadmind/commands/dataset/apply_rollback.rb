module VpsAdmind
  class Commands::Dataset::ApplyRollback < Commands::Base
    handle 5211

    include Utils::System
    include Utils::Zfs

    def exec
      origin = "#{@pool_fs}/#{@dataset_name}"

      zfs(:umount, nil, origin)

      # Move subdatasets from original dataset to the rollbacked one
      children = []
      descendants = []

      # Sort direct children and descendants
      @descendant_datasets.each do |ds|
        ds['relative_name'] = ds['full_name'].sub("#{@dataset_name}/", '')
        puts "Relative: #{ds['full_name']} => #{ds['relative_name']}"

        if /\// =~ ds['relative_name']
          descendants << ds
        else
          children << ds
        end
      end
      
      # Disable mount for all descendants
      @descendant_datasets.reverse.each do |ds|
        zfs(:set, 'canmount=off', "#{origin}/#{ds['relative_name']}")
      end

      # Rename direct children
      children.each do |child|
        zfs(
            :rename,
            nil,
            "#{origin}/#{child['relative_name']} #{origin}.rollback/#{child['relative_name']}"
        )
      end

      # Save original properties
      state = dataset_properties(origin, [
          :atime, :compression, :mountpoint, :quota,
          :recordsize, :refquota, :sync
      ])

      # Destroy the original dataset
      zfs(:destroy, '-r', origin)

      # Move the rollbacked one in its place
      zfs(:rename, nil, "#{origin}.rollback #{origin}")

      # Restore original properties
      state.apply_to(origin)

      # Restore canmount and mount all datasets
      zfs(:set, 'canmount=on', origin)
      zfs(:mount, nil, origin)

      @descendant_datasets.each do |ds|
        zfs(:set, 'canmount=on', "#{origin}/#{ds['relative_name']}")
        zfs(:mount, nil, "#{origin}/#{ds['relative_name']}")
      end

      ok
    end
  end
end
