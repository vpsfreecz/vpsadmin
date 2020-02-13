module NodeCtld
  class Commands::Vps::PopulateConfig < Commands::Base
    handle 4005
    needs :system, :osctl, :vps

    def exec
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.backup

        @network_interfaces.each do |netif_opts|
          netif = VpsConfig::NetworkInterface.new(netif_opts['name'])

          netif_opts['routes'].each do |route_opts|
            netif.add_route(VpsConfig::Route.new(
              IPAddress.parse("#{route_opts['addr']}/#{route_opts['prefix']}"),
              route_opts['via'],
              route_opts['shaper']['class_id'],
              route_opts['shaper']['max_tx'],
              route_opts['shaper']['max_rx'],
            ))
          end

          cfg.network_interfaces << netif
        end
      end

      ok
    end

    def rollback
      cfg = VpsConfig.open(@pool_fs, @vps_id)

      if cfg.backup_exist?
        cfg.restore
      elsif cfg.exist?
        cfg.destroy(backup: false)
      end

      ok
    end
  end
end
