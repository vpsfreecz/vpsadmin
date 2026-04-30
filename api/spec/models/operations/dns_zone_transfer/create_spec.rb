# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZoneTransfer::Create do
  def host_addr(ip_address)
    parts = ip_address.ip_addr.split('.').map(&:to_i)
    parts[-1] += 1
    parts.join('.')
  end

  it 'builds a zone transfer and passes it to the create chain' do
    zone = create_dns_zone!(name: "transfer-#{SecureRandom.hex(3)}.example.test.")
    network = create_private_network!(split_prefix: 24)
    ip = create_ipv4_address_in_network!(network: network, location: SpecSeed.location, user: SpecSeed.user)
    host_ip = HostIpAddress.create!(ip_address: ip, ip_addr: host_addr(ip), user_created: true)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::DnsZoneTransfer::Create).to receive(:fire2) do |args:|
      [chain, args.first]
    end

    ret_chain, transfer = described_class.run(
      dns_zone: zone,
      host_ip_address: host_ip,
      peer_type: :secondary_type
    )

    expect(ret_chain).to eq(chain)
    expect(transfer.dns_zone).to eq(zone)
    expect(transfer.host_ip_address).to eq(host_ip)
    expect(transfer).to be_secondary_type
    expect(TransactionChains::DnsZoneTransfer::Create).to have_received(:fire2).with(args: [transfer])
  end
end
