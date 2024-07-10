module NodeCtld
  class Commands::DnsServerZone::UpdateRecord < Commands::Base
    handle 5505
    needs :dns

    def exec
      get_dns_server_zone.update_record(@record['new'])
      ok
    end

    def rollback
      get_dns_server_zone.update_record(@record['original'])
      ok
    end
  end
end
