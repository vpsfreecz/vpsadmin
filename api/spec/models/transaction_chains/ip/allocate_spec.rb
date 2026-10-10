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

  it 'does not widen a multi-address batch when another pool becomes enabled after its first reservation' do
    fixture = create_allocation_fixture(ip_count: 1)
    later_network = create_private_network!(location: SpecSeed.location, address: '198.51.100.0', purpose: :vps)
    later_ip = create_ipv4_address_in_network!(network: later_network, location: SpecSeed.location)
    later_network.update!(enabled: false)
    changed = false
    allow_any_instance_of(IpAddress).to receive(:lock_current!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
      result = original.call(*args, **kwargs)
      unless changed
        changed = true
        later_network.update!(enabled: true)
      end
      result
    end

    _chain, allocated = use_chain_method_in_root!(
      described_class, method: :allocate_to_netif, args: [resource, fixture[:netif], 2], kwargs: { strict: false }
    )
    expect(allocated).to eq(1)
    expect(fixture[:ip_addresses].first.reload.network_interface_id).to eq(fixture[:netif].id)
    expect(later_ip.reload.network_interface_id).to be_nil
    expect(later_network.reload.enabled?).to be(true)
  end

  it 'treats an empty captured destination set as no capacity even with a populated continuity map' do
    fixture = create_allocation_fixture(ip_count: 1)
    networks = Network.lock_for_admission!([fixture[:network].id])
    _chain, allocated = use_chain_method_in_root!(
      described_class, method: :allocate_to_netif, args: [resource, fixture[:netif], 1],
                       kwargs: { strict: false, admission_networks: networks, candidate_network_ids: [] }
    )
    expect(allocated).to eq(0)
    expect(fixture[:ip_addresses].first.reload.network_interface_id).to be_nil
  end

  it 'rejects a selected address outside its captured network identities' do
    fixture = create_allocation_fixture(ip_count: 1)
    other_network = create_private_network!(location: SpecSeed.location, address: '198.51.100.0', purpose: :vps)
    other_ip = create_ipv4_address_in_network!(network: other_network, location: SpecSeed.location)
    networks = Network.lock_for_admission!([fixture[:network].id])
    allow(IpAddress).to receive(:pick_from_admitted_networks!).and_return(other_ip)
    expect do
      use_chain_method_in_root!(
        described_class, method: :allocate_to_netif, args: [resource, fixture[:netif], 1],
                         kwargs: { admission_networks: networks, candidate_network_ids: [fixture[:network].id] }
      )
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse, /network changed/)
    expect(other_ip.reload.network_interface_id).to be_nil
  end

  it 'rejects legacy owned addresses with no charge provenance' do
    fixture = create_allocation_fixture(ip_count: 1, ownership: true)
    ip = fixture[:ip_addresses].first
    ip.update!(user: user, charged_environment: nil)
    expect do
      use_chain_method_in_root!(described_class, method: :allocate_to_netif,
                                                 args: [resource, fixture[:netif], 1])
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalidLocation, /reconcile its accounting/)
    expect(ip.reload.user_id).to eq(user.id)
    expect(ip.charged_environment_id).to be_nil
    expect(ip.network_interface_id).to be_nil
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

  [true, false].each do |ownership|
    it "selects an unowned candidate instead of an incompatible owned charge (ownership=#{ownership})" do
      fixture = create_allocation_fixture(ip_count: 1, ownership: ownership)
      charge_location = ownership ? SpecSeed.other_location : SpecSeed.location
      owned = create_ipv4_address_in_network!(
        network: fixture[:network], location: charge_location, user: user
      )
      config = user.environment_user_configs.find_by!(environment: charge_location.environment)
      before = config.ipv4_private

      _chain, chowned = use_chain_method_in_root!(
        described_class, method: :allocate_to_netif, args: [resource, fixture[:netif], 1]
      )

      expect(chowned).to eq(1)
      expect(fixture[:ip_addresses].first.reload.network_interface_id).to eq(fixture[:netif].id)
      expect(owned.reload.network_interface_id).to be_nil
      expect(owned.charged_environment_id).to eq(charge_location.environment_id)
      expect(config.reload.ipv4_private).to eq(before)
    end
  end

  it 'reuses an owned allocation already charged in the destination without another charge' do
    fixture = create_allocation_fixture(ip_count: 0, ownership: true)
    ip = create_ipv4_address_in_network!(network: fixture[:network], location: SpecSeed.location, user: user)
    _chain, chowned = use_chain_method_in_root!(
      described_class, method: :allocate_to_netif, args: [resource, fixture[:netif], 1]
    )
    expect(chowned).to eq(0)
    expect(ip.reload.network_interface_id).to eq(fixture[:netif].id)
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
  end

  it 'rejects a selected owned address whose current charge is in another environment' do
    fixture = create_allocation_fixture(ip_count: 0, ownership: true)
    ip = create_ipv4_address_in_network!(network: fixture[:network], location: SpecSeed.other_location, user: user)
    allow(IpAddress).to receive_messages(candidate_network_ids: [fixture[:network].id], pick_from_admitted_networks!: ip)
    expect do
      use_chain_method_in_root!(described_class, method: :allocate_to_netif,
                                                 args: [resource, fixture[:netif], 1])
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse, /no longer available/)
    expect(ip.reload.network_interface_id).to be_nil
    expect(ip.charged_environment_id).to eq(SpecSeed.other_environment.id)
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

  it 'excludes disabled pools including owned detached reuse' do
    fixture = create_allocation_fixture(ip_count: 1, ownership: true)
    create_ipv4_address_in_network!(network: fixture[:network], location: SpecSeed.location, user: user)
    fixture[:network].update!(enabled: false)
    expect do
      use_chain_method_in_root!(described_class, method: :allocate_to_netif,
                                                 args: [resource, fixture[:netif], 1])
    end.to raise_error(VpsAdmin::API::Exceptions::ConfigurationError, /no ipv4_private/)
    expect(fixture[:network].ip_addresses.pluck(:network_interface_id)).to all(be_nil)
  end

  it 'rejects a stale selected address after its network is disabled' do
    fixture = create_allocation_fixture(ip_count: 1)
    ip = fixture[:ip_addresses].first
    fixture[:network].update!(enabled: false)
    allow(IpAddress).to receive_messages(candidate_network_ids: [fixture[:network].id], pick_from_admitted_networks!: ip)
    expect do
      use_chain_method_in_root!(described_class, method: :allocate_to_netif,
                                                 args: [resource, fixture[:netif], 1])
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled/)
    expect(ip.reload.network_interface_id).to be_nil
  end

  %i[owner purpose location].each do |changed|
    it "rechecks #{changed} after reserving a previously selected address" do
      fixture = create_allocation_fixture(ip_count: 1)
      ip = fixture[:ip_addresses].first
      network = fixture[:network]
      case changed
      when :owner
        IpAddress.where(id: ip.id).update_all(user_id: SpecSeed.other_user.id,
                                              charged_environment_id: SpecSeed.environment.id)
      when :purpose
        network.update!(purpose: :export)
      when :location
        LocationNetwork.where(network_id: network.id).delete_all
      end
      allow(IpAddress).to receive_messages(candidate_network_ids: [network.id], pick_from_admitted_networks!: ip)

      expect do
        use_chain_method_in_root!(described_class, method: :allocate_to_netif,
                                                   args: [resource, fixture[:netif], 1])
      end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse, /no longer available/)
      expect(ip.reload.network_interface_id).to be_nil
      expect(ip.user_id).to eq(SpecSeed.other_user.id) if changed == :owner
    end
  end
end
