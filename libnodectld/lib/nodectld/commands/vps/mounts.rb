require 'fileutils'

module NodeCtld
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :pool, :vps

    def exec
      @mounts.each { |m| DelayedMounter.change_mount(@vps_id, m) }

      # Backup original files
      files.each do |path|
        FileUtils.cp(path, backup_path(path)) if File.exist?(path)
      end

      # Write new mounts
      File.open("#{mounts_config}.new", 'w') do |f|
        f.puts(YAML.dump(@mounts))
      end

      File.rename("#{mounts_config}.new", mounts_config)

      # Install osctl hooks
      if @mounts.any?
        install_hooks

      else
        uninstall_hooks
      end

      ok
    end

    def rollback
      # Restore original files
      files.each do |path|
        backup = backup_path(path)
        File.rename(backup, path) if File.exists?(backup)
      end

      ok
    end

    protected
    def install_hooks
      hooks.each do |hook|
        dst = hook_path(hook)

        FileUtils.cp(
          File.join(NodeCtld.root, 'templates', 'ct', 'hook', hook),
          "#{dst}.new"
        )

        File.chmod(0500, "#{dst}.new")
        File.rename("#{dst}.new", dst)
      end
    end

    def uninstall_hooks
      hooks.each do |hook|
        dst = hook_path(hook)
        File.unlink(dst) if File.exist?(dst)
      end
    end

    def hooks
      %w(pre-start post-mount)
    end

    def files
      [mounts_config] + hooks.map {|v| hook_path(v) }
    end

    def hook_path(name)
      File.join(ct_hook_dir, name)
    end

    def backup_path(path)
      "#{path}.backup"
    end
  end
end
