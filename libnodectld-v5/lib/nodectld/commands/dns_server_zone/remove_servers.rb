module NodeCtld
  class Commands::DnsServerZone::RemoveServers < Commands::Base
    handle 5508
    needs :dns

    def exec
      remove_servers_from_zone
      ok
    end

    def rollback
      add_servers_to_zone
      ok
    end
  end
end
