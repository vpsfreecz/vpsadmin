module NodeCtld
  module Utils::Pool
    POOL_WORKING_DIR = 'vpsadmin'.freeze
    POOL_WORKING_DIRS = %i[config download mount].freeze
    DOWNLOAD_HEALTHCHECK_FILE = '_vpsadmin-download-healthcheck'.freeze

    def pool_work_root
      POOL_WORKING_DIR
    end

    def pool_working_dirs
      POOL_WORKING_DIRS
    end

    def path_to_pool_working_dir(type)
      "#{pool_work_root}/#{type}"
    end

    def pool_mounted_clone(pool_fs, clone_name)
      "#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{clone_name}"
    end

    def pool_download_dir(pool_fs)
      "/#{pool_fs}/#{path_to_pool_working_dir(:download)}"
    end

    def pool_download_healthcheck_path(pool_fs)
      "#{pool_download_dir(pool_fs)}/#{DOWNLOAD_HEALTHCHECK_FILE}"
    end

    def pool_download_healthcheck_content(pool_id)
      "#{pool_id}\n"
    end

    def ensure_pool_download_healthcheck(pool_fs, pool_id)
      path = pool_download_healthcheck_path(pool_fs)
      tmp = "#{path}.new"

      File.write(tmp, pool_download_healthcheck_content(pool_id))
      File.rename(tmp, path)

      path
    end

    def pool_mounted_download(pool_fs, dl_id)
      "/#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{dl_id}.download"
    end

    def pool_host_mountpoint(pool_fs, mnt_id)
      "/#{pool_fs}/#{path_to_pool_working_dir(:mount)}/#{mnt_id}.mount"
    end
  end
end
