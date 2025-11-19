module NodeCtld
  class Commands::Vps::OsTemplate < Commands::Base
    handle 2013
    needs :libvirt, :vps

    def exec
      set_os_template(@new)
      ok
    end

    def rollback
      set_os_template(@original)
      ok
    end

    protected

    def set_os_template(t)
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.distribution = t['distribution']
        cfg.version = t['version']
        cfg.arch = t['arch']
        cfg.variant = t['variant']

        ConfigDrive.create(@vps_id, cfg)
      end

      return unless domain.active?

      distconfig!(domain, ['os-template-set', t['distribution'], t['version'], t['arch'], t['variant']])
    end
  end
end
