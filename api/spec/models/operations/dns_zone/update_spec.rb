# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::Update do
  it 'passes the zone and attributes to the update chain' do
    zone = create_dns_zone!(name: "update-#{SecureRandom.hex(3)}.example.test.")
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::Update).to receive(:fire2).and_return([chain, zone])

    expect(described_class.run(zone, { enabled: false })).to eq([chain, zone])
    expect(TransactionChains::DnsZone::Update).to have_received(:fire2).with(
      args: [zone, { enabled: false }]
    )
  end
end
