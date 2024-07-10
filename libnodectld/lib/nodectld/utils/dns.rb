require 'tempfile'

module NodeCtld
  module Utils::Dns
    # @return [DnsServerZone]
    def get_dns_server_zone(**kwargs)
      zone_attrs = {
        name: @name,
        source: @source,
        default_ttl: @default_ttl,
        nameservers: @nameservers,
        primaries: @primaries,
        secondaries: @secondaries,
        serial: @serial,
        email: @email,
        enabled: @enabled,
        tsig_algorithm: @tsig_algorithm,
        tsig_key: @tsig_key
      }
      zone_attrs.update(kwargs)

      DnsServerZone.new(**zone_attrs)
    end
  end
end
