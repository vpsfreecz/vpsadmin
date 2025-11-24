module NodeCtld
  class Commands::Vps::Reinstall < Commands::Base
    handle 3003

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.distribution = @distribution
        cfg.version = @version
        cfg.arch = @arch
        cfg.variant = @variant
        cfg.save

        ConfigDrive.create(@vps_id, cfg)
      end

      ok
    end
  end
end
