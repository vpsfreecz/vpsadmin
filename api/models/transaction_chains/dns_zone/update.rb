module TransactionChains
  class DnsZone::Update < ::TransactionChain
    label 'Update zone'
    allow_empty

    # @param dns_zone [::DnsZone]
    # @param attrs [Hash]
    # @return [::DnsZone]
    def link_chain(dns_zone, attrs)
      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      attrs.each_key do |k|
        next if %i[label default_ttl email tsig_algorithm tsig_key enabled].include?(k)

        raise ArgumentError, "Cannot change DnsZone attribute #{k.inspect}, not supported"
      end

      dns_zone.assign_attributes(attrs)

      if !dns_zone.default_ttl_changed? \
         && !dns_zone.email_changed? \
         && !dns_zone.tsig_algorithm_changed? \
         && !dns_zone.tsig_key_changed? \
         && !dns_zone.enabled_changed?
        dns_zone.save!
        return dns_zone
      else
        raise ActiveRecord::RecordInvalid, dns_zone unless dns_zone.valid?
      end

      db_attrs = {}
      db_attrs[:label] = attrs[:label] if attrs.has_key?(:label)

      new_attrs = {}
      original_attrs = {}

      %i[default_ttl email tsig_algorithm tsig_key enabled].each do |attr|
        next unless dns_zone.send(:"#{attr}_changed?")

        new_attrs[attr] = dns_zone.send(attr)
        original_attrs[attr] = dns_zone.send(:"#{attr}_was")
      end

      return dns_zone if new_attrs.empty?

      dns_zone.dns_server_zones.each do |dns_server_zone|
        append_t(
          Transactions::DnsServerZone::Update,
          args: [dns_server_zone],
          kwargs: {
            new: new_attrs,
            original: original_attrs
          }
        )

        # Disabled zones or external zones without any configured primaries are not
        # enabled in bind configuration and a targeted reload would fail.
        reload_zone = !dns_zone.enabled_changed? && (dns_zone.internal_source? || dns_zone.dns_zone_transfers.primary_type.any?)

        append_t(
          Transactions::DnsServer::Reload,
          args: [dns_server_zone.dns_server],
          kwargs: reload_zone ? { zone: dns_zone.name } : {}
        )
      end

      if empty?
        dns_zone.save!
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          db_attrs.update(new_attrs)
          t.edit(dns_zone, **db_attrs)
        end
      end

      dns_zone
    end
  end
end
