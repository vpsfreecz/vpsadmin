# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsServerZone::Destroy do
  it 'returns the chain from Destroy.fire2' do
    zone = create_dns_zone!(name: "server-zone-destroy-#{SecureRandom.hex(3)}.example.test.")
    server = create_dns_server!(node: SpecSeed.node)
    server_zone = create_dns_server_zone!(dns_zone: zone, dns_server: server)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsServerZone::Destroy).to receive(:fire2).and_return([chain, server_zone])

    expect(described_class.run(server_zone)).to eq(chain)
    expect(TransactionChains::DnsServerZone::Destroy).to have_received(:fire2).with(args: [server_zone])
  end
end
