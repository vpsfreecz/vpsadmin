module VpsAdmind
  class Commands::Dataset::DownloadSnapshot < Commands::Base
    handle 5004
    needs :system, :pool

    def exec
      # On ZoL, snapshots in .zfs are mounted using automounts, so for tar
      # to work properly, it must be accessed before, so that it is already mounted
      # when tar is launched.
      Dir.entries("/#{@pool_fs}/#{@dataset_name}/.zfs/snapshot/#{@snapshot}")

      syscmd("#{$CFG.get(:bin, :mkdir)} \"#{secret_dir_path}\"")
      syscmd("#{$CFG.get(:bin, :tar)} -czf \"#{file_path}\" -C \"/#{@pool_fs}/#{@dataset_name}/.zfs/snapshot\" \"#{@snapshot}\"")
    end

    def rollback
      syscmd("#{$CFG.get(:bin, :rm)} -f \"#{file_path}\"") if File.exists?(file_path)
      syscmd("#{$CFG.get(:bin, :rmdir)} \"#{secret_dir_path}\"") if File.exists?(secret_dir_path)
      ok
    end

    protected
    def snapshot_path

    end

    def secret_dir_path
      "/#{@pool_fs}/#{path_to_pool_working_dir(:download)}/#{@secret_key}"
    end

    def file_path
      "#{secret_dir_path}/#{@file_name}"
    end
  end
end
