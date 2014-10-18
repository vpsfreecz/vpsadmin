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

      # Destroy the original dataset
      zfs(:destroy, '-r', origin)

      # Mova the rollbacked one in its place
      zfs(:rename, nil, "#{origin}.rollback #{origin}")
    end
  end
end
