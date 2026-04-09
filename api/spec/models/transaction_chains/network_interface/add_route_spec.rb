# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::AddRoute do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'locks resources, adds routes, reallocates resources, and updates exports' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "add-route-#{SecureRandom.hex(4)}"
    )
    env = fixture[:vps].node.location.environment
    env.update!(user_ip_ownership: true)

    export_network = create_private_network!(location: fixture[:pool].node.location)
    create_ipv4_address_in_network!(
      network: export_network,
      location: fixture[:pool].node.location
    )

    export = create_export_for_dataset!(
      dataset_in_pool: fixture[:dataset_in_pool],
      enabled: false
    ).first
    export.update!(all_vps: true)

    existing_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.70'
    )
    existing_ip.update!(order: 4)

    via_parent_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      addr: '192.0.2.71'
    )
    via_addr = via_parent_ip.host_ip_addresses.take!

    routed_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      addr: '192.0.2.72'
    )
    host_addr = routed_ip.host_ip_addresses.take!

    chain, = described_class.fire(
      fixture[:netif],
      [routed_ip],
      host_addrs: [host_addr],
      via: via_addr
    )

    expect(tx_classes(chain)).to eq(
      [
        Transactions::NetworkInterface::AddRoute,
        Transactions::NetworkInterface::AddHostIp,
        Transactions::Utils::NoOp,
        Transactions::Export::AddHosts
      ]
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['NetworkInterface', fixture[:netif].id],
      ['Vps', fixture[:vps].id],
      ['IpAddress', routed_ip.id]
    )
    expect(tx_payload(chain, Transactions::NetworkInterface::AddRoute)).to include(
      'addr' => routed_ip.addr,
      'via' => via_addr.ip_addr,
      'id' => routed_ip.id,
      'user_id' => user.id
    )

    route_confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'IpAddress' && row.row_pks == { 'id' => routed_ip.id }
    end

    expect(route_confirmation.attr_changes).to include(
      'network_interface_id' => fixture[:netif].id,
      'route_via_id' => via_addr.id,
      'order' => 5,
      'charged_environment_id' => env.id,
      'user_id' => user.id
    )
    expect(host_addr.reload.order).to eq(0)
    expect(confirmations_for(chain).map(&:class_name)).to include('ClusterResourceUse')
    expect(export.reload.export_hosts.pluck(:ip_address_id)).to eq([routed_ip.id])
  end
end
