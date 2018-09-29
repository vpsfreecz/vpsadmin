module NodeCtld
  class Commands::NetworkInterface::CreateVethRouted < Commands::Base
    handle 2018
    needs :system, :osctl, :vps

    def exec
      osctl(
        %i(ct netif new routed),
        [@vps_id, @name],
        {hwaddr: @mac_address}
      )
    end

    def rollback
      osctl(%i(ct netif del), [@vps_id, @name])
    end
  end
end
