# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::HostIpAddress::Update do
  def host_addr(ip_address)
    parts = ip_address.ip_addr.split('.').map(&:to_i)
    parts[-1] += 1
    parts.join('.')
  end

  let(:network) { create_private_network!(split_prefix: 24) }
  let(:ip_address) { create_ipv4_address_in_network!(network: network, location: SpecSeed.location) }
  let(:host_ip) do
    HostIpAddress.create!(
      ip_address: ip_address,
      ip_addr: host_addr(ip_address),
      user_created: true
    )
  end

  it 'dispatches SetReverseRecord when reverse_record_value is present' do
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::SetReverseRecord).to receive(:fire2).and_return([chain, host_ip])

    expect(described_class.run(host_ip, reverse_record_value: 'ptr.example.test.')).to eq([chain, host_ip])
    expect(TransactionChains::DnsZone::SetReverseRecord).to have_received(:fire2).with(
      args: [host_ip, 'ptr.example.test.']
    )
  end

  it 'dispatches UnsetReverseRecord when reverse_record_value is empty' do
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZone::UnsetReverseRecord).to receive(:fire2).and_return([chain, host_ip])

    expect(described_class.run(host_ip, reverse_record_value: '')).to eq([chain, host_ip])
    expect(TransactionChains::DnsZone::UnsetReverseRecord).to have_received(:fire2).with(args: [host_ip])
  end
end
