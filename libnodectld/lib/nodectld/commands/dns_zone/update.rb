module NodeCtld
  class Commands::DnsZone::Update < Commands::Base
    handle 5503
    needs :dns

    def exec
      zone = get_dns_zone(**get_zone_attrs('new'))
      zone.save
      ok
    end

    def rollback
      zone = get_dns_zone(**get_zone_attrs('original'))
      zone.save
      ok
    end

    protected

    def get_zone_attrs(dir)
      ret = {}

      %w[default_ttl nameservers serial email].each do |attr|
        changes = instance_variable_get(:"@#{dir}")
        ret[attr.to_sym] = changes[attr] if changes.has_key?(attr)
      end

      ret
    end
  end
end
