# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Ip::Allocate do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }
  let(:resource) { ClusterResource.find_by!(name: 'ipv4_private') }

  def create_allocation_fixture(ip_count:, ownership: false, export: false)
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "allocate-ip-#{SecureRandom.hex(4)}"
    )
    env = fixture[:vps].node.location.environment
    env.update!(user_ip_ownership: ownership)
    network = create_private_network!(
      location: fixture[:pool].node.location,
      purpose: :vps
    )
    ips = Array.new(ip_count) do
      create_ipv4_address_in_network!(
        network: network,
        location: fixture[:pool].node.location
      )
    end

    if export
      export_row = create_export_for_dataset!(
        dataset_in_pool: fixture[:dataset_in_pool],
        enabled: false
      ).first
      export_row.update!(all_vps: true)
    end

    fixture.merge(environment: env, network: network, ip_addresses: ips)
  end

  it 'allocates routes with increasing order and charges the VPS environment' do
    fixture = create_allocation_fixture(ip_count: 2)

    chain, chowned = use_chain_method_in_root!(
      described_class,
      method: :allocate_to_netif,
      args: [resource, fixture[:netif], 2]
    )

    expect(chowned).to eq(2)
    expect(tx_classes(chain)).to eq(
      [
        Transactions::NetworkInterface::AddRoute,
        Transactions::NetworkInterface::AddRoute
      ]
    )
    expect(fixture[:ip_addresses].map { |ip| ip.reload.order }).to eq([0, 1])
    expect(fixture[:ip_addresses].map { |ip| ip.reload.network_interface_id }).to all(eq(fixture[:netif].id))
    expect(fixture[:ip_addresses].map { |ip| ip.reload.charged_environment_id }).to all(eq(fixture[:environment].id))
  end

  it 'sets ownership when location IP ownership is enabled' do
    fixture = create_allocation_fixture(ip_count: 1, ownership: true)

    _chain, chowned = use_chain_method_in_root!(
      described_class,
      method: :allocate_to_netif,
      args: [resource, fixture[:netif], 1]
    )

    expect(chowned).to eq(1)
    expect(fixture[:ip_addresses].first.reload.user_id).to eq(user.id)
  end

  it 'adds auto host addresses when requested' do
    fixture = create_allocation_fixture(ip_count: 1)
    host_ip = fixture[:ip_addresses].first.host_ip_addresses.take!

    chain, = use_chain_method_in_root!(
      described_class,
      method: :allocate_to_netif,
      args: [resource, fixture[:netif], 1],
      kwargs: { host_addrs: true }
    )

    expect(tx_classes(chain)).to eq(
      [
        Transactions::NetworkInterface::AddRoute,
        Transactions::NetworkInterface::AddHostIp
      ]
    )
    expect(host_ip.reload.order).to eq(0)
  end

  it 'updates all-vps exports with the allocated IP set' do
    fixture = create_allocation_fixture(ip_count: 2, export: true)

    chain, = use_chain_method_in_root!(
      described_class,
      method: :allocate_to_netif,
      args: [resource, fixture[:netif], 2]
    )

    expect(tx_classes(chain)).to include(Transactions::Export::AddHosts)
    expect(
      tx_payload(chain, Transactions::Export::AddHosts)
        .fetch('hosts')
        .map { |host| host.fetch('address') }
    ).to match_array(fixture[:ip_addresses].map(&:to_s))
  end

  it 'returns fewer IPs with strict disabled when the pool runs out' do
    fixture = create_allocation_fixture(ip_count: 1)

    chain, chowned = use_chain_method_in_root!(
      described_class,
      method: :allocate_to_netif,
      args: [resource, fixture[:netif], 2],
      kwargs: { strict: false }
    )

    expect(chowned).to eq(1)
    expect(tx_classes(chain)).to eq([Transactions::NetworkInterface::AddRoute])
  end

  it 'raises when strict allocation cannot find an address' do
    fixture = create_allocation_fixture(ip_count: 0)

    expect do
      use_chain_method_in_root!(
        described_class,
        method: :allocate_to_netif,
        args: [resource, fixture[:netif], 1]
      )
    end.to raise_error(VpsAdmin::API::Exceptions::ConfigurationError, /no ipv4_private address available/)
  end
end
