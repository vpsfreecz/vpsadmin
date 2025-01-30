module NodeCtld
  class Commands::NetworkInterface::CreateVethRouted < Commands::Base
    handle 2018
    needs :system, :osctl, :vps

    def exec
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces << VpsConfig::NetworkInterface.new(@name)
      end

      new_opts = { hwaddr: @mac_address, max_tx: @max_tx, max_rx: @max_rx }

      if @enable
        new_opts[:enable] = true
      else
        new_opts[:disable] = true
      end

      osctl(%i[ct netif new routed], [@vps_id, @name], new_opts)
      NetAccounting.add_netif(@vps_id, @user_id, @netif_id, @name)
      ok
    end

    def rollback
      VpsConfig.edit(@pool_fs, @vps_id) do |cfg|
        cfg.network_interfaces.remove(@name)
      end

      NetAccounting.remove_netif(@vps_id, @netif_id)
      osctl(%i[ct netif del], [@vps_id, @name])
    end
  end
end
