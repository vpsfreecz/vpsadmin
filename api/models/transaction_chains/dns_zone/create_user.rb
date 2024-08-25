module TransactionChains
  class DnsZone::CreateUser < ::TransactionChain
    label 'Zone+'
    allow_empty

    # @param dns_zone [::DnsZone]
    # @param seed_vps [::Vps, nil]
    # @return [::DnsZone]
    def link_chain(dns_zone, seed_vps: nil)
      dns_zone.save!

      lock(dns_zone)
      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      seeded_records, seeded_logs = records_for_vps(dns_zone, seed_vps)

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

        seeded_records.each do |r|
          r.update!(confirmed: ::DnsRecord.confirmed(:confirmed))
        end
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.create(dns_zone)
          seeded_records.each { |r| t.create(r) }
          seeded_logs.each { |log| t.just_create(log) }
        end
      end

      dns_zone
    end

    protected

    def records_for_vps(dns_zone, vps)
      return [[], []] if vps.nil?

      host_addrs = {}

      ::HostIpAddress
        .joins(ip_address: %i[network_interface network])
        .includes(ip_address: :network)
        .where.not(order: nil)
        .where(network_interfaces: { vps_id: vps.id })
        .where(networks: { role: 'public_access' })
        .order('network_interfaces.id, host_ip_addresses.`order`')
        .each do |host_ip|
        ip_v = host_ip.ip_address.network.ip_version
        next if host_addrs.has_key?(ip_v)

        host_addrs[ip_v] = host_ip.ip_addr

        break if host_addrs.size == 2
      end

      records = host_addrs.map do |ip_v, addr|
        ::DnsRecord.create!(
          dns_zone:,
          name: '@',
          record_type: ip_v == 4 ? 'A' : 'AAAA',
          content: addr
        )
      end

      logs = records.map do |r|
        ::DnsRecordLog.create!(
          user: ::User.current,
          dns_zone:,
          dns_zone_name: dns_zone.name,
          change_type: 'create_record',
          name: r.name,
          record_type: r.record_type,
          attr_changes: { content: r.content },
          transaction_chain: current_chain
        )
      end

      [records, logs]
    end
  end
end
