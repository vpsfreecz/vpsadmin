module NodeCtld
  class Commands::NetworkInterface::RemoveVethRouted < Commands::Base
    handle 2019
    needs :system, :osctl, :vps

    def exec
      osctl(%i(ct netif del), [@vps_id, @name])
    end

    def rollback
      osctl(
        %i(ct netif new routed),
        [@vps_id, @name],
        {hwaddr: @mac_address}
      )
    end
  end
end
