module NodeCtld
  class Commands::Vps::PopulateConfig < Commands::Base
    handle 4005
    needs :system, :osctl, :vps

    def exec
      VpsConfig.create_or_replace(@pool_fs, @vps_id) do |cfg|
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
      cfg.destroy(backup: false) if cfg.exist?
      ok
    end
  end
end
