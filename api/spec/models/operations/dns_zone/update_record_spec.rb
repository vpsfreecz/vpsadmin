# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::UpdateRecord do
  let(:zone) { create_dns_zone!(name: "update-record-#{SecureRandom.hex(3)}.example.test.") }

  it 'rejects managed records' do
    record = create_dns_record!(dns_zone: zone).tap { |r| r.update!(managed: true) }

    expect do
      described_class.run(record, content: '198.51.100.11')
    end.to raise_error(VpsAdmin::API::Exceptions::DnsRecordManagedError)
  end

  it 'enables dynamic updates by creating a token' do
    record = create_dns_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.10')

    ret_chain, ret_record = described_class.run(record, dynamic_update_enabled: true, comment: 'token only')

    expect(ret_chain).to be_nil
    expect(ret_record.reload.update_token).to be_present
  end

  it 'disables dynamic updates by deleting the token' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.10')
    token_id = record.update_token_id

    ret_chain, ret_record = described_class.run(record, dynamic_update_enabled: false, comment: 'token off')

    expect(ret_chain).to be_nil
    expect(ret_record.reload.update_token).to be_nil
    expect(Token.exists?(token_id)).to be(false)
  end

  it 'saves database-only changes without a chain' do
    record = create_dns_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.10')

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire)

    ret_chain, ret_record = described_class.run(record, comment: 'changed')

    expect(ret_chain).to be_nil
    expect(ret_record.reload.comment).to eq('changed')
    expect(TransactionChains::DnsZone::UpdateRecord).not_to have_received(:fire)
  end

  it 'normalizes content, validates and fires the update chain for operational changes' do
    record = create_dns_record!(dns_zone: zone, name: 'alias', record_type: 'CNAME', content: 'old.example.test.')
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire).and_return([chain, record])

    ret_chain, ret_record = described_class.run(record, content: 'new.example.test')

    expect(ret_chain).to eq(chain)
    expect(ret_record.content).to eq('new.example.test.')
    expect(TransactionChains::DnsZone::UpdateRecord).to have_received(:fire).with(record)
  end
end
