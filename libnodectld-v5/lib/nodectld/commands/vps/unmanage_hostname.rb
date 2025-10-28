require 'libosctl'

module NodeCtld
  class Commands::Vps::UnmanageHostname < Commands::Base
    handle 2016
    needs :system, :libvirt, :vps

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.hostname = nil

        ConfigDrive.create(@vps_id, cfg)
      end

      distconfig!(domain, %w[hostname-unset])

      ok
    end

    def rollback
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.hostname = OsCtl::Lib::Hostname.new(@hostname)

        ConfigDrive.create(@vps_id, cfg)
      end

      distconfig!(domain, ['hostname-set', @hostname])

      ok
    end
  end
end
