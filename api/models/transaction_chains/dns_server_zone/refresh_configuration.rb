module TransactionChains
  class DnsServerZone::RefreshConfiguration < ::TransactionChain
    label 'Refresh DNS server zone configuration'
    allow_empty

    def link_chain(dns_server_zone, original: nil, all_servers: false, configuration: nil)
      lock(dns_server_zone.dns_zone)
      configuration ||= ::DnsServerZone.lock_configuration([dns_server_zone.dns_zone])
      dns_server_zone = configuration.fetch(:server_zones).find { |entry| entry.id == dns_server_zone.id }
      raise ActiveRecord::RecordNotFound unless dns_server_zone &&
                                                %i[confirm_create confirmed].include?(dns_server_zone.dns_zone.confirmed)

      if all_servers
        configuration.fetch(:server_zones).each do |server_zone|
          use_chain(self.class, args: [server_zone], kwargs: { configuration: })
        end
        return dns_server_zone
      end
      concerns(
        :affect,
        [dns_server_zone.dns_zone.class.name, dns_server_zone.dns_zone_id],
        [dns_server_zone.dns_server.class.name, dns_server_zone.dns_server_id]
      )

      attrs = dns_server_zone.configuration_attrs(**configuration)

      append_t(
        Transactions::DnsServerZone::Update,
        args: [dns_server_zone],
        kwargs: { new: attrs, original: original || attrs }
      )
      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      dns_server_zone
    end
  end
end
