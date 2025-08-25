module NodeCtld
  class Commands::NetworkInterface::Enable < Commands::Base
    handle 2032
    needs :system, :osctl, :vps

    def exec
      osctl(%i[ct netif set], [@vps_id, @veth_name], { enable: true })
    end

    def rollback
      osctl(%i[ct netif set], [@vps_id, @veth_name], { disable: true })
    end
  end
end
