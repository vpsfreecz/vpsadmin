# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZoneTransfer::Destroy do
  def host_addr(ip_address)
    parts = ip_address.ip_addr.split('.').map(&:to_i)
    parts[-1] += 1
    parts.join('.')
  end

  it 'passes the transfer to the destroy chain and returns its response' do
    zone = create_dns_zone!(name: "transfer-destroy-#{SecureRandom.hex(3)}.example.test.")
    network = create_private_network!(split_prefix: 24)
    ip = create_ipv4_address_in_network!(network: network, location: SpecSeed.location, user: SpecSeed.user)
    host_ip = HostIpAddress.create!(ip_address: ip, ip_addr: host_addr(ip), user_created: true)
    transfer = create_dns_zone_transfer!(dns_zone: zone, host_ip_address: host_ip, peer_type: :secondary_type)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZoneTransfer::Destroy).to receive(:fire2).and_return([chain, transfer])

    expect(described_class.run(transfer)).to eq([chain, transfer])
    expect(TransactionChains::DnsZoneTransfer::Destroy).to have_received(:fire2).with(args: [transfer])
  end
end
