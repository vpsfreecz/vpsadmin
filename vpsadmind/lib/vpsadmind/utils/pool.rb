module VpsAdmind
  module Utils::Pool
    POOL_WORKING_DIR = 'vpsadmin'
    POOL_WORKING_DIRS = [:mount, :download]

    def pool_work_root
      POOL_WORKING_DIR
    end

    def pool_working_dirs
      POOL_WORKING_DIRS
    end

    def path_to_pool_working_dir(type)
      "#{pool_work_root}/#{type}"
    end

    def pool_mounted_snapshot(pool_fs, clone_name)
      "#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{clone_name}"
    end
  end
end
