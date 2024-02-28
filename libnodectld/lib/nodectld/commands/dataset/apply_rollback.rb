module NodeCtld
  class Commands::Dataset::ApplyRollback < Commands::Base
    handle 5211

    include Utils::System
    include Utils::Zfs
    include Utils::OsCtl

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

        if %r{/} =~ ds['relative_name']
          descendants << [ds, ds_state]
        else
          children << [ds, ds_state]
        end
      end

      # rubocop:disable Style/HashEachMethods
      # Disable mount for all descendants
      @descendant_datasets.reverse.each do |ds, _ds_state|
        zfs(:set, 'canmount=off', "#{origin}/#{ds['relative_name']}")
      end

      # Rename direct children
      children.each do |child, _ds_state|
        zfs(
          :rename,
          nil,
          "#{origin}/#{child['relative_name']} #{origin}.rollback/#{child['relative_name']}"
        )
      end
      # rubocop:enable Style/HashEachMethods

      # Save original properties
      state = dataset_properties(origin, %i[
                                   atime compression mountpoint quota
                                   recordsize refquota sync canmount
                                   uidmap gidmap
                                 ])

      # Destroy the original dataset
      osctl(%i[trash-bin dataset add], origin)

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

      # zfs share -a may report an error and exit with status `1` e.g. if dataset
      # `tank/ct` isn't mounted. We're generally not interested in failures
      # of this kind as there's nothing that vpsAdmin can do about it.
      zfs(:share, '-a', '', valid_rcs: [1])

      ok
    end
  end
end
