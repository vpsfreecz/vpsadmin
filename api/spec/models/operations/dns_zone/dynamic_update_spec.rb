# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::DynamicUpdate do
  let(:zone) { create_dns_zone!(name: "dyn-#{SecureRandom.hex(3)}.example.test.") }

  def token_for(record)
    record.update_token.token
  end

  it 'resolves tokens only for A and AAAA records' do
    record = create_dns_update_token_record!(
      dns_zone: zone,
      record_type: 'TXT',
      name: 'txt',
      content: 'old'
    )

    expect do
      described_class.run(build_request(ip: '198.51.100.10'), token_for(record))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'uses Client-IP before other request addresses' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire) { |arg| [chain, arg] }

    ret_chain, ret_record = described_class.run(
      build_request(
        ip: '198.51.100.30',
        extra_env: {
          'HTTP_CLIENT_IP' => '198.51.100.10',
          'HTTP_X_REAL_IP' => '198.51.100.20'
        }
      ),
      token_for(record)
    )

    expect(ret_chain).to eq(chain)
    expect(ret_record.content).to eq('198.51.100.10')
  end

  it 'uses X-Real-IP when Client-IP is absent' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire) { |arg| [instance_double(TransactionChain), arg] }

    _chain, ret_record = described_class.run(
      build_request(ip: '198.51.100.30', extra_env: { 'HTTP_X_REAL_IP' => '198.51.100.20' }),
      token_for(record)
    )

    expect(ret_record.content).to eq('198.51.100.20')
  end

  it 'uses request.ip when proxy headers are absent' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire) { |arg| [instance_double(TransactionChain), arg] }

    _chain, ret_record = described_class.run(build_request(ip: '198.51.100.30'), token_for(record))

    expect(ret_record.content).to eq('198.51.100.30')
  end

  it 'raises OperationError for invalid client IP addresses' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')

    expect do
      described_class.run(build_request(extra_env: { 'HTTP_CLIENT_IP' => 'not-an-ip' }), token_for(record))
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Unable to parse client IP address')
  end

  it 'rejects IPv6 addresses for A records' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')

    expect do
      described_class.run(build_request(ip: '2001:db8::1'), token_for(record))
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Record is of type A and client address is IPv6')
  end

  it 'rejects IPv4 addresses for AAAA records' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'AAAA', content: '2001:db8::1')

    expect do
      described_class.run(build_request(ip: '198.51.100.10'), token_for(record))
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Record is of type AAAA and client address is IPv4')
  end

  it 'returns the record without a chain when content is unchanged' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.10')

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire)

    expect(described_class.run(build_request(ip: '198.51.100.10'), token_for(record))).to eq([nil, record])
    expect(TransactionChains::DnsZone::UpdateRecord).not_to have_received(:fire)
  end

  it 'validates changed records and fires UpdateRecord' do
    record = create_dns_update_token_record!(dns_zone: zone, record_type: 'A', content: '198.51.100.1')
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::UpdateRecord).to receive(:fire) { |arg| [chain, arg] }

    ret_chain, ret_record = described_class.run(build_request(ip: '198.51.100.10'), token_for(record))

    expect(ret_chain).to eq(chain)
    expect(ret_record.content).to eq('198.51.100.10')
    expect(TransactionChains::DnsZone::UpdateRecord).to have_received(:fire).with(record)
  end
end
