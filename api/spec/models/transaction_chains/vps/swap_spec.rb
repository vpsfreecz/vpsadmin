# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Swap do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Object).to receive(:get_vps_shaper_limit).and_return(nil)
    # rubocop:enable RSpec/AnyInstance
  end

  def create_swap_fixture(same_location: false, secondary_user: user, with_primary_netif: true, with_secondary_netif: true)
    src_node = create_node!(location: SpecSeed.location, role: :node, name: "swap-src-#{SecureRandom.hex(3)}")
    dst_node = create_node!(
      location: same_location ? SpecSeed.location : SpecSeed.other_location,
      role: :node,
      name: "swap-dst-#{SecureRandom.hex(3)}"
    )
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    dst_pool = create_pool!(node: dst_node, role: :hypervisor)
    src_pool.update!(migration_public_key: 'spec-src-pubkey')
    dst_pool.update!(migration_public_key: 'spec-dst-pubkey')

    ensure_numeric_resources!(user: user, environment: src_node.location.environment)
    ensure_numeric_resources!(user: secondary_user, environment: dst_node.location.environment)
    ensure_numeric_resources!(user: user, environment: dst_node.location.environment)

    src_dataset, src_dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "swap-src-#{SecureRandom.hex(4)}"
    )
    dst_dataset, dst_dip = create_dataset_with_pool!(
      user: user,
      pool: dst_pool,
      name: "swap-dst-#{SecureRandom.hex(4)}"
    )

    allocate_dip_diskspace!(src_dip, user: user, value: 10_240)
    allocate_dip_diskspace!(dst_dip, user: secondary_user, value: 10_240)

    primary_vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: src_dip)
    secondary_vps = create_vps_for_dataset!(
      user: secondary_user,
      node: dst_node,
      dataset_in_pool: dst_dip
    )
    primary_vps.update!(manage_hostname: true)
    secondary_vps.update!(manage_hostname: true)

    allocate_vps_resources!(primary_vps, user: user, cpu: 2, memory: 2048, swap: 256)
    allocate_vps_resources!(secondary_vps, user: secondary_user, cpu: 1, memory: 1024, swap: 0)

    primary_netif = create_network_interface!(primary_vps, name: 'eth0') if with_primary_netif
    secondary_netif = create_network_interface!(secondary_vps, name: 'eth0') if with_secondary_netif

    if primary_netif
      create_ip_address!(
        network: SpecSeed.network_v4,
        location: src_node.location,
        network_interface: primary_netif,
        addr: "192.0.2.#{20 + SecureRandom.random_number(20)}"
      )
    end

    if secondary_netif
      create_ip_address!(
        network: SpecSeed.network_v4,
        location: dst_node.location,
        network_interface: secondary_netif,
        addr: "192.0.2.#{60 + SecureRandom.random_number(20)}"
      )
    end

    [primary_vps, secondary_vps]
  end

  it 'rejects swap within the same location' do
    primary_vps, secondary_vps = create_swap_fixture(same_location: true)

    expect do
      described_class.fire(primary_vps, secondary_vps, resources: false, hostname: false, expirations: false)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /swap within one location/)
  end

  it 'rejects swap between different owners' do
    primary_vps, secondary_vps = create_swap_fixture(secondary_user: SpecSeed.other_user)

    expect do
      described_class.fire(primary_vps, secondary_vps, resources: false, hostname: false, expirations: false)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /access denied/)
  end

  it 'rejects swap when network-interface topology does not match' do
    primary_vps, secondary_vps = create_swap_fixture(with_secondary_netif: false)

    expect do
      described_class.fire(primary_vps, secondary_vps, resources: false, hostname: false, expirations: false)
    end.to raise_error(RuntimeError, /network interface mismatch/)
  end

  it 'builds the expected broad migration and network-mutation subsequences for a cross-location swap' do
    primary_vps, secondary_vps = create_swap_fixture

    chain, = described_class.fire(
      primary_vps,
      secondary_vps,
      resources: false,
      hostname: true,
      expirations: false
    )
    classes = tx_classes(chain)
    send_config_rows = transactions_for(chain).select do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::SendConfig
    end
    stop_tx = transactions_for(chain).find do |tx|
      Transaction.for_type(tx.handle) == Transactions::Vps::Stop && tx.vps_id == primary_vps.id
    end
    first_add_route = transactions_for(chain).find do |tx|
      Transaction.for_type(tx.handle) == Transactions::NetworkInterface::AddRoute
    end

    expect(classes.count(Transactions::Vps::SendConfig)).to eq(2)
    expect(classes.count(Transactions::Vps::SendRootfs)).to eq(2)
    expect(classes.count(Transactions::Vps::SendState)).to eq(2)
    expect(classes.count(Transactions::NetworkInterface::DelRoute)).to eq(2)
    expect(classes.count(Transactions::NetworkInterface::AddRoute)).to eq(2)
    expect(classes.count(Transactions::Vps::Resources)).to eq(2)
    expect(classes.count(Transactions::Vps::Hostname)).to eq(2)
    expect(classes).to include(Transactions::Utils::NoOp, Transactions::Vps::Stop)
    expect(send_config_rows.map(&:vps_id)).to eq([secondary_vps.id, primary_vps.id])
    expect(stop_tx.vps_id).to eq(primary_vps.id)
    expect(stop_tx.id).to be < first_add_route.id
    expect(ObjectHistory.where(tracked_object: primary_vps, event_type: 'swap').count).to eq(1)
    expect(ObjectHistory.where(tracked_object: secondary_vps, event_type: 'swap').count).to eq(1)
  end
end
