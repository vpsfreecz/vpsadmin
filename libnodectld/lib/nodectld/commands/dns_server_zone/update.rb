module NodeCtld
  class Commands::DnsServerZone::Update < Commands::Base
    handle 5503
    needs :dns

    def exec
      zone = get_dns_server_zone(**get_zone_attrs('new'))
      zone.save
      DnsConfig.instance.update_zone(zone)
      ok
    end

    def rollback
      zone = get_dns_server_zone(**get_zone_attrs('original'))
      zone.save
      DnsConfig.instance.update_zone(zone)
      ok
    end

    protected

    def get_zone_attrs(dir)
      ret = {}

      %w[
        default_ttl
        nameservers
        serial
        email
        primaries
        secondaries
        tsig_algorithm
        tsig_key
        enabled
      ].each do |attr|
        changes = instance_variable_get(:"@#{dir}")
        ret[attr.to_sym] = changes[attr] if changes.has_key?(attr)
      end

      ret
    end
  end
end
