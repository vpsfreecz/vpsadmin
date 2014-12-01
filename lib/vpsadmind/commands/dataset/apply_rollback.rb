module VpsAdmind
  class Commands::Dataset::ApplyRollback < Commands::Base
    handle 5211

    include Utils::System
    include Utils::Zfs

    def exec
      origin = "#{@pool_fs}/#{@dataset_name}"

      # Move subdatasets from original dataset to the rollbacked one
      @child_datasets.each do |child|
        zfs(:rename, nil, "#{origin}/#{child} #{origin}.rollback/#{child}")
      end

      # Save original properties
      state = dataset_properties(origin, [
          :atime, :compression, :mountpoint, :quota,
          :recordsize, :refquota, :sync
      ])

      # Destroy the original dataset
      zfs(:destroy, '-r', origin)

      # Mova the rollbacked one in its place
      zfs(:rename, nil, "#{origin}.rollback #{origin}")

      # Restore original properties
      state.apply_to(origin)

      zfs(:set, 'canmount=on', origin)
      zfs(:mount, nil, origin)
    end
  end
end
