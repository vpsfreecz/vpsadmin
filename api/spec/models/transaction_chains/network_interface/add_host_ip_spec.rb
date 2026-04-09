# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::AddHostIp do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'orders host addresses per IP version and writes log rows' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "host-ip-#{SecureRandom.hex(4)}"
    )

    existing_v4_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.80'
    )
    existing_v4_ip.host_ip_addresses.take!.update!(order: 1)

    existing_v6_ip = create_ip_address!(
      network: SpecSeed.network_v6,
      location: SpecSeed.other_location,
      network_interface: fixture[:netif],
      addr: '2001:db8::80'
    )
    existing_v6_ip.host_ip_addresses.take!.update!(order: 4)

    new_v4_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.81'
    )
    new_v6_ip = create_ip_address!(
      network: SpecSeed.network_v6,
      location: SpecSeed.other_location,
      network_interface: fixture[:netif],
      addr: '2001:db8::81'
    )

    v4_addr = new_v4_ip.host_ip_addresses.take!
    v6_addr = new_v6_ip.host_ip_addresses.take!

    chain, = described_class.fire(fixture[:netif], [v4_addr, v6_addr])

    expect(tx_classes(chain)).to eq(
      [
        Transactions::NetworkInterface::AddHostIp,
        Transactions::NetworkInterface::AddHostIp
      ]
    )
    expect(v4_addr.reload.order).to eq(2)
    expect(v6_addr.reload.order).to eq(5)
    expect(confirmations_for(chain).select { |row| row.class_name == 'HostIpAddress' }
             .map(&:confirm_type)).to eq(%w[edit_before_type edit_before_type])
    expect(
      fixture[:vps].object_histories.where(event_type: 'host_addr_add').pluck(:event_data)
    ).to include(
      { 'id' => v4_addr.id, 'addr' => v4_addr.ip_addr },
      { 'id' => v6_addr.id, 'addr' => v6_addr.ip_addr }
    )
  end

  it 'rejects host addresses routed to a different interface' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "host-ip-check-#{SecureRandom.hex(4)}"
    )
    other_netif = create_network_interface!(fixture[:vps], name: 'eth1')
    other_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: other_netif,
      addr: '192.0.2.82'
    )
    other_addr = other_ip.host_ip_addresses.take!

    expect do
      described_class.fire(fixture[:netif], [other_addr])
    end.to raise_error(/belongs to network routed to interface/)
  end
end
