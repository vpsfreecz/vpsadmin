# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsServerZone::Create do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def build_internal_fixture
    dns_zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "internal-#{SecureRandom.hex(4)}.example.test."
    )

    secondary_server = create_dns_server!(
      node: create_node!(name: "dns-secondary-#{SecureRandom.hex(3)}"),
      name: "ns-secondary-#{SecureRandom.hex(3)}"
    )
    primary_server = create_dns_server!(
      node: create_node!(name: "dns-primary-#{SecureRandom.hex(3)}"),
      name: "ns-primary-#{SecureRandom.hex(3)}"
    )

    create_dns_server_zone!(
      dns_zone: dns_zone,
      dns_server: secondary_server,
      zone_type: :secondary_type
    )
    create_dns_server_zone!(
      dns_zone: dns_zone,
      dns_server: primary_server,
      zone_type: :primary_type
    )

    new_server = create_dns_server!(
      node: create_node!(name: "dns-new-#{SecureRandom.hex(3)}"),
      name: "ns-new-#{SecureRandom.hex(3)}"
    )

    {
      dns_zone: dns_zone,
      dns_server_zone: DnsServerZone.new(
        dns_zone: dns_zone,
        dns_server: new_server,
        zone_type: :primary_type
      )
    }
  end

  def build_external_fixture
    dns_zone = create_dns_zone!(
      user: user,
      source: :external_source,
      email: nil,
      name: "external-#{SecureRandom.hex(4)}.example.test."
    )

    2.times do
      create_dns_server_zone!(
        dns_zone: dns_zone,
        dns_server: create_dns_server!(
          node: create_node!(name: "dns-ext-#{SecureRandom.hex(3)}"),
          name: "ns-ext-#{SecureRandom.hex(3)}"
        ),
        zone_type: :secondary_type
      )
    end

    new_server = create_dns_server!(
      node: create_node!(name: "dns-ext-new-#{SecureRandom.hex(3)}"),
      name: "ns-ext-new-#{SecureRandom.hex(3)}"
    )

    {
      dns_zone: dns_zone,
      dns_server_zone: DnsServerZone.new(
        dns_zone: dns_zone,
        dns_server: new_server,
        zone_type: :secondary_type
      )
    }
  end

  it 'creates internal zones and updates secondary and primary siblings differently' do
    fixture = build_internal_fixture

    chain, dns_server_zone = described_class.fire(fixture[:dns_server_zone])

    expect(dns_server_zone).to be_persisted
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::Create,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload
      ]
    )

    secondary_payload = tx_payload(chain, Transactions::DnsServerZone::AddServers, nth: 0)
    primary_payload = tx_payload(chain, Transactions::DnsServerZone::AddServers, nth: 1)
    server_opts = [{ 'ip_addr' => dns_server_zone.ip_addr, 'tsig_key' => nil }]

    expect(secondary_payload).to include(
      'nameservers' => [dns_server_zone.dns_server.name],
      'primaries' => server_opts,
      'secondaries' => []
    )
    expect(primary_payload).to include(
      'nameservers' => [dns_server_zone.dns_server.name],
      'primaries' => [],
      'secondaries' => []
    )
  end

  it 'creates external zones and adds the new server to primaries and secondaries' do
    fixture = build_external_fixture

    chain, dns_server_zone = described_class.fire(fixture[:dns_server_zone])

    server_opts = [{ 'ip_addr' => dns_server_zone.ip_addr, 'tsig_key' => nil }]

    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::Create,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::AddServers,
        Transactions::DnsServer::Reload
      ]
    )
    2.times do |idx|
      expect(tx_payload(chain, Transactions::DnsServerZone::AddServers, nth: idx)).to include(
        'primaries' => server_opts,
        'secondaries' => server_opts
      )
    end
  end
end
