require 'tempfile'

module NodeCtld
  module Utils::Dns
    # @return [DnsZone]
    def get_dns_zone(**kwargs)
      zone_attrs = {
        name: @name,
        default_ttl: @default_ttl,
        nameservers: @nameservers,
        serial: @serial,
        email: @email
      }
      zone_attrs.update(kwargs)

      DnsZone.new(**zone_attrs)
    end
  end
end
