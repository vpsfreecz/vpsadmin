module NodeCtld
  class Commands::Dataset::RemoveDownload < Commands::Base
    handle 5005
    needs :system, :pool

    def exec
      syscmd("#{$CFG.get(:bin, :rm)} -f \"#{file_path}\"") if File.exist?(file_path)

      return unless File.exist?(secret_dir_path)

      syscmd("#{$CFG.get(:bin, :rmdir)} \"#{secret_dir_path}\"")
    end

    protected

    def secret_dir_path
      "/#{@pool_fs}/#{path_to_pool_working_dir(:download)}/#{@secret_key}"
    end

    def file_path
      "#{secret_dir_path}/#{@file_name}"
    end
  end
end
