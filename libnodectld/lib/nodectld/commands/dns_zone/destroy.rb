module NodeCtld
  class Commands::DnsZone::Destroy < Commands::Base
    handle 5502
    needs :dns

    def exec
      zone = get_dns_zone
      zone.destroy
      DnsConfig.instance.remove_zone(zone)
      ok
    end

    def rollback
      zone = get_dns_zone
      zone.replace_all_records(@records)
      DnsConfig.instance.add_zone(zone)
      ok
    end
  end
end
