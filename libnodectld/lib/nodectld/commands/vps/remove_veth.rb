module NodeCtld
  class Commands::Vps::RemoveVeth < Commands::Base
    handle 2019
    needs :system, :osctl, :vps

    def exec
      osctl(%i(ct netif del), [@vps_id, @veth_name])
    end

    def rollback
      osctl(
        %i(ct netif new routed),
        [@vps_id, @veth_name],
        {via: @interconnecting_networks.values}
      )
    end
  end
end
