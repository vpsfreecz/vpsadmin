# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::HostIpAddress::Create do
  def host_addr(ip_address, offset = 1)
    parts = ip_address.ip_addr.split('.').map(&:to_i)
    parts[-1] += offset
    parts.join('.')
  end

  let(:network) { create_private_network!(split_prefix: 24) }
  let(:ip_address) do
    create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location,
      user: SpecSeed.user
    )
  end

  it 'creates a user-created host IP when the address belongs to the owning IP address' do
    host_ip = described_class.run(ip_address, host_addr(ip_address))

    expect(host_ip).to be_persisted
    expect(host_ip.ip_address).to eq(ip_address)
    expect(host_ip).to be_user_created
  end

  it 'raises OperationError for unparsable addresses' do
    expect do
      described_class.run(ip_address, 'not-an-ip')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Unable to parse IP address')
  end

  it 'raises OperationError when the address is outside the owning IP address range' do
    expect do
      described_class.run(ip_address, '203.0.113.10')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /does not belong/)
  end

  it 'raises OperationError for duplicate host IPs' do
    addr = host_addr(ip_address)
    described_class.run(ip_address, addr)

    expect do
      described_class.run(ip_address, addr)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /already exists/)
  end
end
