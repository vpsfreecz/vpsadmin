# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsZoneTransfer::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_transfer_host_ip
    network = create_private_network!(
      location: SpecSeed.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location,
      user: user
    )

    ip.host_ip_addresses.take!
  end

  it 'removes internal secondary transfer servers from all server zones' do
    zone = create_dns_zone!(user: user, source: :internal_source)
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :primary_type
    )
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(
        node: create_node!(name: "dns-transfer-rm-#{SecureRandom.hex(3)}"),
        name: "ns-transfer-rm-#{SecureRandom.hex(3)}"
      ),
      zone_type: :secondary_type
    )
    transfer = create_dns_zone_transfer!(
      dns_zone: zone,
      host_ip_address: create_transfer_host_ip,
      peer_type: :secondary_type
    )

    chain, = described_class.fire(transfer)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp
      ]
    )
    expect(
      tx_payloads(chain)
        .select { |payload| payload['secondaries'] }
        .map { |payload| payload.fetch('secondaries').first.fetch('ip_addr') }
    ).to eq([transfer.ip_addr, transfer.ip_addr])
    expect(transfer.reload.confirmed).to eq(:confirm_destroy)
    expect(confirmations_for(chain).find { |row| row.class_name == 'DnsZoneTransfer' }.confirm_type).to eq(
      'destroy_type'
    )
  end

  it 'removes external primary transfer servers from secondary server zones' do
    zone = create_dns_zone!(user: user, source: :external_source, email: nil)
    create_dns_server_zone!(
      dns_zone: zone,
      dns_server: create_dns_server!(node: SpecSeed.node),
      zone_type: :secondary_type
    )
    transfer = create_dns_zone_transfer!(
      dns_zone: zone,
      host_ip_address: create_transfer_host_ip,
      peer_type: :primary_type
    )

    chain, = described_class.fire(transfer)

    expect(tx_classes(chain)).to include(
      Transactions::DnsServerZone::RemoveServers,
      Transactions::DnsServer::Reload
    )
    expect(tx_payload(chain, Transactions::DnsServerZone::RemoveServers).fetch('primaries')).to eq(
      [{ 'ip_addr' => transfer.ip_addr, 'tsig_key' => nil }]
    )
  end

  it 'destroys empty transfers immediately' do
    zone = create_dns_zone!(user: user, source: :internal_source)
    transfer = create_dns_zone_transfer!(
      dns_zone: zone,
      host_ip_address: create_transfer_host_ip,
      peer_type: :secondary_type
    )

    chain, = described_class.fire(transfer)

    expect(chain).to be_nil
    expect(DnsZoneTransfer.where(id: transfer.id)).to be_empty
  end
end
