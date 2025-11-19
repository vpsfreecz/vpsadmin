require 'libosctl'

module NodeCtld
  class Commands::Vps::Hostname < Commands::Base
    handle 2004
    needs :system, :libvirt, :vps

    def exec
      set_hostname(@hostname)
    end

    def rollback
      set_hostname(@original)
    end

    protected

    def set_hostname(hostname)
      distconfig!(domain, ['hostname-set', hostname], run: true)

      VpsConfig.edit(@vps_id) do |cfg|
        cfg.hostname = OsCtl::Lib::Hostname.new(hostname)

        ConfigDrive.create(@vps_id, cfg)
      end

      ok
    end
  end
end
