# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsServerZone::Create do
  it 'validates the new server-zone row and passes it to the create chain' do
    zone = create_dns_zone!(name: "server-zone-#{SecureRandom.hex(3)}.example.test.")
    server = create_dns_server!(node: SpecSeed.node)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsServerZone::Create).to receive(:fire2) do |args:|
      [chain, args.first]
    end

    ret_chain, dns_server_zone = described_class.run(
      dns_zone: zone,
      dns_server: server,
      zone_type: :primary_type
    )

    expect(ret_chain).to eq(chain)
    expect(dns_server_zone).to be_valid
    expect(dns_server_zone.dns_zone).to eq(zone)
    expect(dns_server_zone.dns_server).to eq(server)
    expect(TransactionChains::DnsServerZone::Create).to have_received(:fire2).with(args: [dns_server_zone])
  end

  it 'raises RecordInvalid for invalid server-zone rows' do
    zone = create_dns_zone!(
      name: "external-zone-#{SecureRandom.hex(3)}.example.test.",
      source: :external_source,
      email: nil
    )
    server = create_dns_server!(node: SpecSeed.node)

    expect do
      described_class.run(dns_zone: zone, dns_server: server, zone_type: :primary_type)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
