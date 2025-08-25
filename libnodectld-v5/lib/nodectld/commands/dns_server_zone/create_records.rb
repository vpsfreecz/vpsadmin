module NodeCtld
  class Commands::DnsServerZone::CreateRecords < Commands::Base
    handle 5504
    needs :dns

    def exec
      zone = get_dns_server_zone

      @records.each do |r|
        zone.create_record(r)
      end

      ok
    end

    def rollback
      zone = get_dns_server_zone

      @records.each do |r|
        zone.delete_record(r)
      end

      ok
    end
  end
end
