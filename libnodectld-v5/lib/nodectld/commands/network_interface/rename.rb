module NodeCtld
  class Commands::NetworkInterface::Rename < Commands::Base
    handle 2020
    needs :libvirt, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).rename(@new_guest_name)
      NetAccounting.rename_netif(@vps_id, @netif_id, @new_guest_name)
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @new_guest_name).rename(@guest_name)
      NetAccounting.rename_netif(@vps_id, @netif_id, @guest_name)
      ok
    end
  end
end
