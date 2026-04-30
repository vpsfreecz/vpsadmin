# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::HostIpAddress::Destroy do
  def host_addr(ip_address, offset = 1)
    parts = ip_address.ip_addr.split('.').map(&:to_i)
    parts[-1] += offset
    parts.join('.')
  end

  let(:network) { create_private_network!(split_prefix: 24) }
  let(:ip_address) { create_ipv4_address_in_network!(network: network, location: SpecSeed.location) }

  it 'rejects non-user-created rows' do
    host_ip = ip_address.host_ip_addresses.first

    expect do
      described_class.run(host_ip)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /cannot be deleted/)
  end

  it 'rejects assigned host IP rows' do
    host_ip = HostIpAddress.create!(
      ip_address: ip_address,
      ip_addr: host_addr(ip_address),
      order: 1,
      user_created: true
    )

    expect do
      described_class.run(host_ip)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /is in use/)
  end

  it 'dispatches destroy for user-created unassigned rows' do
    host_ip = HostIpAddress.create!(
      ip_address: ip_address,
      ip_addr: host_addr(ip_address),
      user_created: true
    )
    chain = instance_double(TransactionChain)

    allow(TransactionChains::HostIpAddress::Destroy).to receive(:fire).and_return([chain, host_ip])

    expect(described_class.run(host_ip)).to eq([chain, host_ip])
    expect(TransactionChains::HostIpAddress::Destroy).to have_received(:fire).with(host_ip)
  end
end
