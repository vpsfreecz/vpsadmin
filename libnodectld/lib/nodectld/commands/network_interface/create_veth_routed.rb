module NodeCtld
  class Commands::NetworkInterface::CreateVethRouted < Commands::Base
    handle 2018
    needs :system, :osctl, :vps

    def exec
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces << VpsConfig::NetworkInterface.new(@name)
      end

      osctl(
        %i(ct netif new routed),
        [@vps_id, @name],
        {hwaddr: @mac_address}
      )
    end

    def rollback
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces.remove(@name)
      end

      osctl(%i(ct netif del), [@vps_id, @name])
    end
  end
end
