module NodeCtld
  class Commands::Vps::RescueLeave < Commands::Base
    handle 2038
    needs :system

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.os_family = @os_family
        cfg.distribution = @distribution
        cfg.version = @version
        cfg.arch = @arch
        cfg.variant = @variant
        cfg.hostname = @hostname
        cfg.rescue_label = nil
        cfg.rescue_rootfs_mountpoint = nil
        cfg.save

        ConfigDrive.create(@vps_id, cfg)
      end

      ok
    end
  end
end
