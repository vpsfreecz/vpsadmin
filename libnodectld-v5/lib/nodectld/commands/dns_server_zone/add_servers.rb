module NodeCtld
  class Commands::DnsServerZone::AddServers < Commands::Base
    handle 5507
    needs :dns

    def exec
      add_servers_to_zone
      ok
    end

    def rollback
      remove_servers_from_zone
      ok
    end
  end
end
