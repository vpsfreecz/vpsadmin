require 'fileutils'

module NodeCtld
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :pool

    def exec
      cfg = VpsConfig.open(@pool_fs, @vps_id)

      # Backup original config
      cfg.backup

      # Write new mounts
      cfg.mounts = @mounts.map { |v| VpsConfig::Mount.load(v) }
      cfg.save

      install_hooks(cfg)

      ok
    end

    def rollback
      # Restore original config
      cfg = VpsConfig.open(@pool_fs, @vps_id)
      cfg.restore

      install_hooks(cfg)

      ok
    end

    protected

    def install_hooks(cfg)
      hook_installer = CtHookInstaller.new(@pool_fs, @vps_id)
      hooks = %w[pre-start post-mount]

      if cfg.mounts.any?
        hook_installer.install_hooks(hooks)
      else
        hook_installer.uninstall_hooks(hooks)
      end
    end
  end
end
