# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::DestroyRecord do
  let(:zone) { create_dns_zone!(name: "destroy-record-#{SecureRandom.hex(3)}.example.test.") }

  it 'rejects managed records' do
    record = create_dns_record!(dns_zone: zone).tap { |r| r.update!(managed: true) }

    expect do
      described_class.run(record)
    end.to raise_error(VpsAdmin::API::Exceptions::DnsRecordManagedError)
  end

  it 'returns the chain from DestroyRecord.fire' do
    record = create_dns_record!(dns_zone: zone)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::DestroyRecord).to receive(:fire).and_return([chain, record])

    expect(described_class.run(record)).to eq(chain)
    expect(TransactionChains::DnsZone::DestroyRecord).to have_received(:fire).with(record)
  end
end
