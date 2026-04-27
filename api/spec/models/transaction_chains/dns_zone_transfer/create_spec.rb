# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZoneTransfer::Create do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_transfer_host_ip(with_reverse: false)
    network = create_private_network!(
      location: SpecSeed.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location,
      user: user
    )
    host_ip = ip.host_ip_addresses.take!

    if with_reverse
      zone = create_dns_zone!(source: :internal_source)
      record = create_dns_record!(
        dns_zone: zone,
        name: 'peer',
        record_type: 'PTR',
        content: 'ns-peer.example.test.'
      )
      host_ip.update!(reverse_dns_record: record)
    end

    host_ip
  end

  it 'adds internal secondary transfer servers to all server zones' do
    zone = create_dns_zone!(user: user, source: :internal_source)
    primary = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node, name: "ns-primary-#{SecureRandom.hex(3)}"),
      zone_type: :primary_type
    )
    secondary = create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: create_node!(name: "dns-secondary-#{SecureRandom.hex(3)}"),
        name: "ns-secondary-#{SecureRandom.hex(3)}"
      ),
      zone_type: :secondary_type
    )
    host_ip = create_transfer_host_ip(with_reverse: true)
    transfer = DnsZoneTransfer.new(
      dns_zone: zone,
      host_ip_address: host_ip,
      peer_type: :secondary_type
    )

    chain, created = described_class.fire(transfer)
    server_opts = [{ 'ip_addr' => host_ip.ip_addr, 'tsig_key' => nil }]

    expect(created).to be_persisted
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(tx_payload(chain, Transactions::DnsServerZone::AddServers, nth: 0)).to include(
      'name' => primary.dns_zone.name,
      'nameservers' => ['ns-peer.example.test.'],
      'secondaries' => server_opts
    )
    expect(tx_payload(chain, Transactions::DnsServerZone::AddServers, nth: 1)).to include(
      'name' => secondary.dns_zone.name,
      'nameservers' => [],
      'secondaries' => server_opts
    )
    expect(confirmations_for(chain).find { |row| row.class_name == 'DnsZoneTransfer' }.confirm_type).to eq(
      'create_type'
    )
  end

  it 'adds external primary transfer servers to secondary server zones' do
    zone = create_dns_zone!(user: user, source: :external_source, email: nil)
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :secondary_type
    )
    host_ip = create_transfer_host_ip
    tsig_key = create_dns_tsig_key!(user: user)
    transfer = DnsZoneTransfer.new(
      dns_zone: zone,
      host_ip_address: host_ip,
      dns_tsig_key: tsig_key,
      peer_type: :primary_type
    )

    chain, = described_class.fire(transfer)
    payload = tx_payload(chain, Transactions::DnsServerZone::AddServers)

    expect(payload.fetch('primaries')).to eq(
      [
        {
          'ip_addr' => host_ip.ip_addr,
          'tsig_key' => {
            'name' => tsig_key.name,
            'algorithm' => tsig_key.algorithm,
            'secret' => tsig_key.secret
          }
        }
      ]
    )
    expect(tx_classes(chain)).to include(Transactions::DnsServer::Reload)
  end

  it 'confirms empty transfer creation immediately' do
    zone = create_dns_zone!(user: user, source: :internal_source)
    transfer = DnsZoneTransfer.new(
      dns_zone: zone,
      host_ip_address: create_transfer_host_ip,
      peer_type: :secondary_type
    )

    chain, created = described_class.fire(transfer)

    expect(chain).to be_nil
    expect(created.reload.confirmed).to eq(:confirmed)
  end
end
