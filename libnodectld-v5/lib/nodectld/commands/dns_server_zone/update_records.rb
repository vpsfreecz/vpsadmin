module NodeCtld
  class Commands::DnsServerZone::UpdateRecords < Commands::Base
    handle 5505
    needs :dns

    def exec
      zone = get_dns_server_zone

      @records.each do |r|
        zone.update_record(r['new'])
      end

      ok
    end

    def rollback
      zone = get_dns_server_zone

      @records.each do |r|
        zone.update_record(r['original'])
      end

      ok
    end
  end
end
