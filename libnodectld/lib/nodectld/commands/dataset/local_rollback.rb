module NodeCtld
  class Commands::Dataset::LocalRollback < Commands::Base
    handle 5208

    include Utils::System
    include Utils::Zfs

    def exec
      base = "#{@pool_fs}/#{@dataset_name}"

      # Unmount datasets
      begin
        zfs(:umount, nil, base)

      rescue SystemCommandFailed => e
        raise if e.rc != 1 || e.output !~ /not currently mounted/
      end

      # Rollback
      zfs(:rollback, '-r', "#{@pool_fs}/#{@dataset_name}@#{@snapshot}")

      # Remount datasets
      zfs(:mount, nil, base)

      @descendant_datasets.each do |ds|
        zfs(:mount, nil, "#{@pool_fs}/#{ds['full_name']}")
      end

      ok
    end
  end
end
