# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::DestroyUser do
  it 'returns the chain from DestroyUser.fire2' do
    zone = create_dns_zone!(name: "destroy-user-#{SecureRandom.hex(3)}.example.test.", user: SpecSeed.user)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::DestroyUser).to receive(:fire2).and_return([chain, zone])

    expect(described_class.run(zone)).to eq(chain)
    expect(TransactionChains::DnsZone::DestroyUser).to have_received(:fire2).with(args: [zone])
  end
end
