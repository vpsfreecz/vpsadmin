# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::CreateSystem do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def zone_attrs(name:, role: :forward_role, network_address: nil, network_prefix: nil)
    {
      name: name,
      zone_role: role,
      zone_source: :internal_source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: 'dns@example.test',
      reverse_network_address: network_address,
      reverse_network_prefix: network_prefix
    }
  end

  it 'creates a confirmed forward zone and returns it' do
    ret_chain, zone = described_class.run(zone_attrs(name: "system-#{SecureRandom.hex(3)}.example.test."))

    expect(ret_chain).to be_nil
    expect(zone).to be_persisted
    expect(zone).to be_confirmed
    expect(zone).to be_forward_role
  end

  it 'assigns matching IP addresses to reverse zones' do
    ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: SpecSeed.location,
      addr: "192.0.2.#{(IpAddress.maximum(:id).to_i % 100) + 50}"
    )

    _, zone = described_class.run(
      zone_attrs(
        name: '2.0.192.in-addr.arpa.',
        role: :reverse_role,
        network_address: '192.0.2.0',
        network_prefix: 24
      )
    )

    expect(ip.reload.reverse_dns_zone).to eq(zone)
  end

  it 'prefers the more specific reverse zone for overlapping networks' do
    ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: SpecSeed.location,
      addr: "192.0.2.#{(IpAddress.maximum(:id).to_i % 50) + 20}"
    )
    _, broad_zone = described_class.run(
      zone_attrs(
        name: '2.0.192.in-addr.arpa.',
        role: :reverse_role,
        network_address: '192.0.2.0',
        network_prefix: 24
      )
    )
    _, specific_zone = described_class.run(
      zone_attrs(
        name: '0-127.2.0.192.in-addr.arpa.',
        role: :reverse_role,
        network_address: '192.0.2.0',
        network_prefix: 25
      )
    )

    expect(ip.reload.reverse_dns_zone).to eq(specific_zone)
    expect(ip.reverse_dns_zone).not_to eq(broad_zone)
  end

  it 'does not persist invalid zones when creation fails' do
    name = "invalid-#{SecureRandom.hex(3)}.example.test."

    expect do
      described_class.run(zone_attrs(name: name).merge(default_ttl: nil))
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(DnsZone.exists?(name: name)).to be(false)
  end
end
