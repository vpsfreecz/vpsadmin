require 'fileutils'

module NodeCtld
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :pool, :vps

    def exec
      @mounts.each { |m| DelayedMounter.change_mount(@vps_id, m) }

      cfg = VpsConfig.open(@pool_fs, @vps_id)

      # Backup original config
      cfg.backup

      # Write new mounts
      cfg.mounts = @mounts.map { |v| VpsConfig::Mount.load(v) }
      cfg.save

      # Install osctl hooks
      if @mounts.any?
        install_hooks

      else
        uninstall_hooks
      end

      ok
    end

    def rollback
      # Restore original config
      cfg = VpsConfig.open(@pool_fs, @vps_id)
      cfg.restore

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
      %w(post-mount)
    end

    def hook_path(name)
      File.join(ct_hook_dir, name)
    end

    def backup_path(path)
      "#{path}.backup"
    end
  end
end
