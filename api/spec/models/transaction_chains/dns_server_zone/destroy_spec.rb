# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DnsServerZone::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def build_internal_fixture
    dns_zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "internal-destroy-#{SecureRandom.hex(4)}.example.test."
    )

    secondary_server = create_dns_server!(
      node: create_node!(name: "dns-destroy-secondary-#{SecureRandom.hex(3)}"),
      name: "ns-destroy-secondary-#{SecureRandom.hex(3)}"
    )
    primary_server = create_dns_server!(
      node: create_node!(name: "dns-destroy-primary-#{SecureRandom.hex(3)}"),
      name: "ns-destroy-primary-#{SecureRandom.hex(3)}"
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

    dns_server_zone = create_dns_server_zone!(
      dns_zone: dns_zone,
      dns_server: create_dns_server!(
        node: create_node!(name: "dns-destroy-new-#{SecureRandom.hex(3)}"),
        name: "ns-destroy-new-#{SecureRandom.hex(3)}"
      ),
      zone_type: :primary_type
    )

    { dns_server_zone: dns_server_zone }
  end

  def build_external_fixture
    dns_zone = create_dns_zone!(
      user: user,
      source: :external_source,
      email: nil,
      name: "external-destroy-#{SecureRandom.hex(4)}.example.test."
    )

    2.times do
      create_dns_server_zone!(
        dns_zone: dns_zone,
        dns_server: create_dns_server!(
          node: create_node!(name: "dns-destroy-ext-#{SecureRandom.hex(3)}"),
          name: "ns-destroy-ext-#{SecureRandom.hex(3)}"
        ),
        zone_type: :secondary_type
      )
    end

    dns_server_zone = create_dns_server_zone!(
      dns_zone: dns_zone,
      dns_server: create_dns_server!(
        node: create_node!(name: "dns-destroy-ext-new-#{SecureRandom.hex(3)}"),
        name: "ns-destroy-ext-new-#{SecureRandom.hex(3)}"
      ),
      zone_type: :secondary_type
    )

    { dns_server_zone: dns_server_zone }
  end

  it 'destroys internal zones and removes the server from siblings correctly' do
    fixture = build_internal_fixture

    chain, returned = described_class.fire(fixture[:dns_server_zone])

    expect(returned).to be_nil
    expect(fixture[:dns_server_zone].reload.confirmed).to eq(:confirm_destroy)
    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::Destroy,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload
      ]
    )

    secondary_payload = tx_payload(chain, Transactions::DnsServerZone::RemoveServers, nth: 0)
    primary_payload = tx_payload(chain, Transactions::DnsServerZone::RemoveServers, nth: 1)
    server_opts = [{ 'ip_addr' => fixture[:dns_server_zone].ip_addr, 'tsig_key' => nil }]

    expect(secondary_payload).to include(
      'nameservers' => [fixture[:dns_server_zone].dns_server.name],
      'primaries' => server_opts,
      'secondaries' => []
    )
    expect(primary_payload).to include(
      'nameservers' => [fixture[:dns_server_zone].dns_server.name],
      'primaries' => [],
      'secondaries' => []
    )
  end

  it 'destroys external zones and removes the server from primaries and secondaries' do
    fixture = build_external_fixture

    chain, = described_class.fire(fixture[:dns_server_zone])
    server_opts = [{ 'ip_addr' => fixture[:dns_server_zone].ip_addr, 'tsig_key' => nil }]

    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::Destroy,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload,
        Transactions::DnsServerZone::RemoveServers,
        Transactions::DnsServer::Reload
      ]
    )
    2.times do |idx|
      expect(tx_payload(chain, Transactions::DnsServerZone::RemoveServers, nth: idx)).to include(
        'primaries' => server_opts,
        'secondaries' => server_opts
      )
    end
  end
end
