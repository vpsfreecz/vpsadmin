require 'tempfile'

module NodeCtld
  module Utils::Dns
    # @return [DnsServerZone]
    def get_dns_server_zone(**kwargs)
      zone_attrs = {
        id: @id,
        name: @name,
        source: @source,
        type: @type,
        default_ttl: @default_ttl,
        nameservers: @nameservers,
        primaries: @primaries,
        secondaries: @secondaries,
        serial: @serial,
        email: @email,
        dnssec_enabled: @dnssec_enabled,
        enabled: @enabled,
        primary_transfer_generation: @primary_transfer_generation,
        primary_transfer_tracking_started_at: @primary_transfer_tracking_started_at,
        probe_source_addrs: @probe_source_addrs
      }
      zone_attrs.update(kwargs)

      DnsServerZone.new(**zone_attrs)
    end

    def add_servers_to_zone
      zone = get_dns_server_zone(nameservers: nil, primaries: nil, secondaries: nil)

      @nameservers.each do |ns|
        zone.nameservers << ns unless zone.nameservers.include?(ns)
      end

      @primaries.each do |srv|
        zone.primaries << srv unless zone.primaries.detect { |v| v['ip_addr'] == srv['ip_addr'] }
      end

      @secondaries.each do |srv|
        zone.secondaries << srv unless zone.secondaries.detect { |v| v['ip_addr'] == srv['ip_addr'] }
      end

      zone.save
      DnsConfig.instance.update_zone(zone)
    end

    def remove_servers_from_zone
      zone = get_dns_server_zone(nameservers: nil, primaries: nil, secondaries: nil)

      if @nameservers.any?
        zone.nameservers.delete_if do |ns|
          @nameservers.include?(ns)
        end
      end

      if @primaries.any?
        zone.primaries.delete_if do |srv|
          @primaries.detect { |v| v['ip_addr'] == srv['ip_addr'] }
        end
      end

      if @secondaries.any?
        zone.secondaries.delete_if do |srv|
          @secondaries.detect { |v| v['ip_addr'] == srv['ip_addr'] }
        end
      end

      zone.save
      DnsConfig.instance.update_zone(zone)
    end
  end
end
