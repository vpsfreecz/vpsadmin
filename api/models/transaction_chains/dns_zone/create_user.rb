module TransactionChains
  class DnsZone::CreateUser < ::TransactionChain
    label 'Zone+'
    allow_empty

    # @param dns_zone [::DnsZone]
    # @return [::DnsZone]
    def link_chain(dns_zone)
      dns_zone.save!

      lock(dns_zone)
      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      ::DnsServer.where(enable_user_dns_zones: true).each do |dns_server|
        dns_server_zone = ::DnsServerZone.create!(
          dns_server:,
          dns_zone:
        )

        append_t(Transactions::DnsServerZone::Create, args: [dns_server_zone]) do |t|
          t.create(dns_server_zone)
        end

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      if empty?
        dns_zone.update!(confirmed: ::DnsZone.confirmed(:confirmed))
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.create(dns_zone)
        end
      end

      dns_zone
    end
  end
end
