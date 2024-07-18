module TransactionChains
  class DnsZone::Update < ::TransactionChain
    label 'Update zone'
    allow_empty

    # @param dns_zone [::DnsZone]
    # @param attrs [Hash]
    # @return [::DnsZone]
    def link_chain(dns_zone, attrs)
      lock(dns_zone)
      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      attrs.each_key do |k|
        next if %i[label default_ttl email enabled].include?(k)

        raise ArgumentError, "Cannot change DnsZone attribute #{k.inspect}, not supported"
      end

      dns_zone.assign_attributes(attrs)

      if !dns_zone.default_ttl_changed? \
         && !dns_zone.email_changed? \
         && !dns_zone.enabled_changed?
        dns_zone.save!
        return dns_zone
      else
        raise ActiveRecord::RecordInvalid, dns_zone unless dns_zone.valid?
      end

      db_attrs = {}
      db_attrs[:label] = dns_zone.label_was if attrs.has_key?(:label)

      new_attrs = {}
      original_attrs = {}

      %i[default_ttl email enabled].each do |attr|
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

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      dns_zone.save!

      return dns_zone if empty?

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        db_attrs.update(original_attrs)
        t.edit_before(dns_zone, **db_attrs)
      end

      dns_zone
    end
  end
end
