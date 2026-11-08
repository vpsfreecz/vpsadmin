module NodeCtld
  class Commands::DnsServerZone::Update < Commands::Base
    handle 5503
    needs :dns

    def exec
      update_zone('new')
    end

    def rollback
      update_zone('original')
    end

    protected

    def update_zone(direction)
      zone = get_dns_server_zone(**get_zone_attrs(direction))
      changes = direction == 'new' ? @new : @original
      %w[primary_transfer_generation primary_transfer_tracking_started_at probe_source_addrs].each do |attr|
        # Explicit nil clears tracking on disable. Constructor nil would load
        # the previous value from disk instead.
        zone.public_send(:"#{attr}=", changes[attr]) if changes.has_key?(attr)
      end
      zone.save
      DnsConfig.instance.update_zone(zone)
      ok
    end

    def get_zone_attrs(dir)
      ret = {}

      %w[
        default_ttl
        nameservers
        serial
        email
        primaries
        secondaries
        dnssec_enabled
        enabled
      ].each do |attr|
        changes = instance_variable_get(:"@#{dir}")
        ret[attr.to_sym] = changes[attr] if changes.has_key?(attr)
      end

      ret
    end
  end
end
