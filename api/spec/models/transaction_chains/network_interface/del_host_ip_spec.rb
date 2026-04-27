# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::DelHostIp do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_assigned_host_ip_fixture
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "del-host-ip-#{SecureRandom.hex(4)}"
    )
    network = create_private_network!(
      location: fixture[:pool].node.location,
      purpose: :vps
    )
    ip = create_ipv4_address_in_network!(
      network: network,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif]
    )
    host_ip = ip.host_ip_addresses.take!
    host_ip.update!(order: 3)

    fixture.merge(ip_address: ip, host_ip_address: host_ip)
  end

  it 'removes one routed host address and logs the removal once' do
    fixture = create_assigned_host_ip_fixture
    chain = nil

    expect do
      chain, = described_class.fire(fixture[:netif], [fixture[:host_ip_address]])
    end.to change {
      fixture[:vps].object_histories.where(event_type: 'host_addr_del').count
    }.by(1)

    expect(tx_classes(chain)).to eq([Transactions::NetworkInterface::DelHostIp])
    expect(
      tx_payload(chain, Transactions::NetworkInterface::DelHostIp)
    ).to include(
      'interface' => fixture[:netif].name,
      'addr' => fixture[:host_ip_address].ip_addr
    )

    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'HostIpAddress'
    end

    expect(confirmation.confirm_type).to eq('edit_after_type')
    expect(confirmation.attr_changes).to eq('order' => nil)
    expect(fixture[:vps].object_histories.where(event_type: 'host_addr_del').count).to eq(1)
  end

  it 'uses a NoOp carrier when removing phony host addresses' do
    fixture = create_assigned_host_ip_fixture

    chain, = described_class.fire(
      fixture[:netif],
      [fixture[:host_ip_address]],
      phony: true
    )

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(
      confirmations_for(chain).select { |row| row.class_name == 'HostIpAddress' }.map(&:attr_changes)
    ).to eq([{ 'order' => nil }])
  end

  it 'rejects host addresses routed to a different interface' do
    fixture = create_assigned_host_ip_fixture
    other_netif = create_network_interface!(fixture[:vps], name: 'eth1')
    other_ip = create_ipv4_address_in_network!(
      network: fixture[:ip_address].network,
      location: fixture[:pool].node.location,
      network_interface: other_netif
    )

    expect do
      described_class.fire(fixture[:netif], [other_ip.host_ip_addresses.take!])
    end.to raise_error(/belongs to network routed to interface/)
  end
end
