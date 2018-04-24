module NodeCtld
  module Utils::Pool
    POOL_WORKING_DIR = 'vpsadmin'
    POOL_WORKING_DIRS = [:config, :download, :mount]

    def pool_work_root
      POOL_WORKING_DIR
    end

    def pool_working_dirs
      POOL_WORKING_DIRS
    end

    def path_to_pool_working_dir(type)
      "#{pool_work_root}/#{type}"
    end

    def pool_mounted_snapshot(pool_fs, snap_id)
      "#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{snap_id}.snapshot"
    end

    def pool_host_mountpoint(pool_fs, mnt_id)
      "/#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{mnt_id}.mount"
    end
  end
end
