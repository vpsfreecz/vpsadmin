# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::DestroySystem do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  it 'destroys a forward zone and returns nil' do
    zone = create_dns_zone!(name: "destroy-#{SecureRandom.hex(3)}.example.test.")

    expect(described_class.run(zone)).to be_nil
    expect(DnsZone.exists?(zone.id)).to be(false)
  end

  it 'clears reverse DNS zone references on matching IP addresses' do
    zone = create_reverse_dns_zone!(
      name: '2.0.192.in-addr.arpa.',
      network_address: '192.0.2.0',
      network_prefix: 24
    )
    ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: SpecSeed.location,
      addr: "192.0.2.#{(IpAddress.maximum(:id).to_i % 100) + 50}"
    )
    ip.update!(reverse_dns_zone: zone)

    described_class.run(zone)

    expect(ip.reload.reverse_dns_zone).to be_nil
  end

  it 'rejects zones that are still assigned to DNS servers' do
    zone = create_dns_zone!(name: "in-use-#{SecureRandom.hex(3)}.example.test.")
    server = create_dns_server!(node: SpecSeed.node)
    create_dns_server_zone!(dns_zone: zone, dns_server: server)

    expect do
      described_class.run(zone)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'DNS zone is in use, remove it from all servers first')
  end
end
