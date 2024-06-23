module NodeCtld
  class Commands::DnsZone::DeleteRecord < Commands::Base
    handle 5506
    needs :dns

    def exec
      get_dns_zone.delete_record(@record)
      ok
    end

    def rollback
      get_dns_zone.create_record(@record)
      ok
    end
  end
end
