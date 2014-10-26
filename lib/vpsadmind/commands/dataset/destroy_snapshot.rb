module VpsAdmind
  class Commands::Dataset::DestroySnapshot < Commands::Base
    handle 5212

    include Utils::System
    include Utils::Zfs

    def exec
      if @branch
        zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}/#{@branch}@#{@snapshot}")

      else
        zfs(:destroy, nil, "#{@pool_fs}/#{@dataset_name}@#{@snapshot}")
      end
    end
  end
end
