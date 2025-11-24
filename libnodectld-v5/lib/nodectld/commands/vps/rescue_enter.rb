module NodeCtld
  class Commands::Vps::RescueEnter < Commands::Base
    handle 2037
    needs :libvirt, :vps

    def exec
      update_config(@rescue_system) do |cfg|
        cfg.rescue_label = @rescue_label
        cfg.rescue_rootfs_mountpoint = @rescue_rootfs_mountpoint
      end

      distconfig!(domain, ['rescue-system-warnings', @rescue_rootfs_mountpoint || ''], run: true)

      ok
    end

    def rollback
      update_config(@standard_system) do |cfg|
        cfg.rescue_label = nil
        cfg.rescue_rootfs_mountpoint = nil
      end

      ok
    end

    protected

    def update_config(hash)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.os_family = hash['os_family']
        cfg.distribution = hash['distribution']
        cfg.version = hash['version']
        cfg.arch = hash['arch']
        cfg.variant = hash['variant']
        cfg.hostname = hash['hostname']
        yield(cfg)

        ConfigDrive.create(@vps_id, cfg)
      end
    end
  end
end
