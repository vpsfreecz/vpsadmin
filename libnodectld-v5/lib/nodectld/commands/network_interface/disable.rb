module NodeCtld
  class Commands::NetworkInterface::Disable < Commands::Base
    handle 2033
    needs :system, :osctl, :vps

    def exec
      osctl(%i[ct netif set], [@vps_id, @veth_name], { disable: true })
    end

    def rollback
      osctl(%i[ct netif set], [@vps_id, @veth_name], { enable: true })
    end
  end
end
