# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::Clear do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'removes routed-via addresses before directly routed addresses' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-clear-#{SecureRandom.hex(4)}"
    )
    fixture[:vps].node.location.environment.update!(user_ip_ownership: true)

    via_parent_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      addr: '192.0.2.95'
    )
    via_addr = via_parent_ip.host_ip_addresses.take!

    routed_via = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.96'
    )
    routed_via.update!(route_via_id: via_addr.id, order: 0)

    routed_direct = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.97'
    )
    routed_direct.update!(order: 1)

    chain, = described_class.fire(fixture[:netif])

    del_route_payloads = transactions_for(chain).filter_map do |tx|
      next unless Transaction.for_type(tx.handle) == Transactions::NetworkInterface::DelRoute

      JSON.parse(tx.input).fetch('input')
    end

    expect(del_route_payloads.map { |payload| payload.fetch('addr') }).to eq(
      [routed_via.addr, routed_direct.addr]
    )
  end
end
