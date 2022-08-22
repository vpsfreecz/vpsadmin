module NodeCtld
  class Commands::NetworkInterface::RemoveVethRouted < Commands::Base
    handle 2019
    needs :system, :osctl, :vps

    def exec
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces.remove(@name)
      end

      osctl(%i(ct netif del), [@vps_id, @name])
    end

    def rollback
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces << VpsConfig::NetworkInterface.new(@name)
      end

      osctl(
        %i(ct netif new routed),
        [@vps_id, @name],
        {hwaddr: @mac_address, max_tx: @max_tx, max_rx: @max_rx},
      )
    end
  end
end
