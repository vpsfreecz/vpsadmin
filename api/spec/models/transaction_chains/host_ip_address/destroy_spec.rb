# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::HostIpAddress::Destroy do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_host_ip
    network = create_private_network!(
      location: SpecSeed.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: SpecSeed.location
    )

    ip.host_ip_addresses.take!
  end

  it 'destroys a host address without reverse DNS immediately' do
    host_ip = create_host_ip

    chain, = described_class.fire(host_ip)

    expect(chain).to be_nil
    expect(HostIpAddress.where(id: host_ip.id)).to be_empty
  end

  it 'unsets reverse DNS and confirms host address destruction' do
    host_ip = create_host_ip
    reverse_zone = create_reverse_dns_zone!
    host_ip.ip_address.update!(reverse_dns_zone: reverse_zone)
    dns_server = create_dns_server!(node: SpecSeed.node)
    create_dns_server_zone!(
      dns_zone: reverse_zone,
      dns_server: dns_server,
      zone_type: :primary_type
    )
    record = create_dns_record!(
      dns_zone: reverse_zone,
      name: '25',
      record_type: 'PTR',
      content: 'host.example.test.'
    )
    host_ip.update!(reverse_dns_record: record)

    chain, = described_class.fire(host_ip)

    expect(tx_classes(chain)).to eq(
      [
        Transactions::DnsServerZone::DeleteRecords,
        Transactions::DnsServer::Reload,
        Transactions::Utils::NoOp,
        Transactions::Utils::NoOp
      ]
    )
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'HostIpAddress' && row.confirm_type == 'just_destroy_type' }
    ).not_to be_nil
    expect(
      chain.transaction_chain_concerns.map { |row| [row.class_name, row.row_id] }
    ).to include(['HostIpAddress', host_ip.id])
  end
end
