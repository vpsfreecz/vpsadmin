# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::CreateRecord do
  let(:zone) { create_dns_zone!(name: "records-#{SecureRandom.hex(3)}.example.test.") }
  let(:chain) { instance_double(TransactionChain) }

  before do
    allow(TransactionChains::DnsZone::CreateRecord).to receive(:fire) do |record|
      [chain, record]
    end
  end

  it 'validates, saves and passes the record to the create chain' do
    ret_chain, record = described_class.run(
      dns_zone: zone,
      name: 'www',
      record_type: 'A',
      content: '198.51.100.10'
    )

    expect(ret_chain).to eq(chain)
    expect(record).to be_persisted
    expect(record.content).to eq('198.51.100.10')
    expect(TransactionChains::DnsZone::CreateRecord).to have_received(:fire).with(record)
  end

  it 'creates update tokens for dynamic A records' do
    _chain, record = described_class.run(
      dns_zone: zone,
      name: 'dyn',
      record_type: 'A',
      content: '198.51.100.10',
      dynamic_update_enabled: true
    )

    expect(record.update_token).to be_present
  end

  it 'rejects dynamic updates on unsupported record types' do
    expect do
      described_class.run(
        dns_zone: zone,
        name: 'txt',
        record_type: 'TXT',
        content: 'value',
        dynamic_update_enabled: true
      )
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Only A and AAAA records can utilize dynamic updates')
  end

  it 'raises RecordInvalid for invalid records' do
    expect do
      described_class.run(
        dns_zone: zone,
        name: 'bad',
        record_type: 'A',
        content: 'not-an-ip'
      )
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
