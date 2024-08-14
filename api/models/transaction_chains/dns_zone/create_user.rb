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

      dns_servers = ::DnsServer.where(enable_user_dns_zones: true)

      # For internal zones, we use all user servers. For external zones,
      # we use only servers for secondary zones, as the primary server is
      # external.
      user_servers =
        if dns_zone.internal_source?
          dns_servers
        else
          dns_servers.secondary_type
        end

      # First create all DNS server zone records
      dns_server_zones = user_servers.map do |dns_server|
        ::DnsServerZone.create!(
          dns_server:,
          dns_zone:,
          zone_type: dns_server.user_dns_zone_type
        )
      end

      # When all server zones are already created, fire transactions
      dns_server_zones.each do |dns_server_zone|
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
