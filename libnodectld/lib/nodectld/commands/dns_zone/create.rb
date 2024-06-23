module NodeCtld
  class Commands::DnsZone::Create < Commands::Base
    handle 5501
    needs :dns

    def exec
      zone = get_dns_zone
      zone.replace_all_records(@records)
      DnsConfig.instance.add_zone(zone)
      ok
    end

    def rollback
      zone = get_dns_zone
      DnsConfig.instance.remove_zone(zone)
      zone.destroy
      ok
    end
  end
end
