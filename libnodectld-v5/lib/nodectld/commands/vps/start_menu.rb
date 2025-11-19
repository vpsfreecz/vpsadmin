module NodeCtld
  class Commands::Vps::StartMenu < Commands::Base
    handle 2030
    needs :libvirt, :vps

    def exec
      set_start_menu(@new_timeout)
      ok
    end

    def rollback
      set_start_menu(@original_timeout)
      ok
    end

    protected

    def set_start_menu(timeout)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.start_menu_timeout = timeout

        ConfigDrive.create(@vps_id, cfg)
      end
    end
  end
end
