module NodeCtld
  class Commands::Vps::CreateVeth < Commands::Base
    handle 2018
    needs :system, :osctl, :vps

    def exec
      osctl(
        %i(ct netif new routed),
        [@vps_id, @veth_name],
        {hwaddr: @mac_address}
      )
    end

    def rollback
      osctl(%i(ct netif del), [@vps_id, @veth_name])
    end
  end
end
