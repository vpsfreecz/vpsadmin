# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Create do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  before do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Object).to receive(:get_vps_shaper_limit).and_return(nil)
    allow_any_instance_of(Object).to receive(:get_netif_shaper_limit).and_return(nil)
    allow_any_instance_of(Object).to receive(:set_netif_shaper_limit).and_return(nil)
    # rubocop:enable RSpec/AnyInstance
  end

  def build_create_vps(os_template:, hostname: 'vps-create-spec')
    node = SpecSeed.node
    pool = create_pool!(node: node, role: :hypervisor, refquota_check: true)
    seed_pool_dataset_properties!(pool)
    ensure_numeric_resources!(user: user, environment: node.location.environment)

    vps = Vps.new(
      user: user,
      node: node,
      hostname: hostname,
      os_template: os_template,
      dns_resolver: nil,
      user_namespace_map: create_user_namespace_map!(user: user),
      object_state: :active,
      confirmed: :confirmed,
      diskspace: 10_240,
      cpu: 2,
      memory: 2048,
      swap: 0
    )

    [pool, vps]
  end

  it 'creates datasets, mounts, features, network configuration, DNS, and start in the expected order' do
    template = create_os_template!(
      manage_dns_resolver: true,
      config: {
        'datasets' => [
          { 'name' => '/' },
          { 'name' => 'var', 'properties' => { 'refquota' => '10%' } },
          { 'name' => 'srv', 'properties' => { 'refquota' => '20%' } }
        ],
        'mounts' => [
          { 'dataset' => 'var', 'mountpoint' => '/var' },
          { 'dataset' => 'srv', 'mountpoint' => '/srv' }
        ],
        'features' => {
          'lxc' => true,
          'impermanence' => true
        }
      }
    )
    _pool, vps = build_create_vps(os_template: template)
    create_ip_address!(location: vps.node.location)

    chain, created_vps = described_class.fire(
      vps,
      ipv4: 1,
      ipv4_private: 0,
      ipv6: 0,
      start: true,
      vps_user_data: nil
    )

    classes = tx_classes(chain)
    root_dip = vps.dataset_in_pool
    vps_resource_scope = ClusterResourceUse.for_obj(vps).joins(user_cluster_resource: :cluster_resource)
    vps_resources = vps_resource_scope.order('cluster_resources.name')
                                      .pluck('cluster_resources.name', :value)
                                      .to_h
    root_resource_scope = ClusterResourceUse.for_obj(root_dip).joins(user_cluster_resource: :cluster_resource)
    diskspace_use = root_resource_scope.find_by!(cluster_resources: { name: 'diskspace' })
    lxc_feature = VpsFeature.find_by!(vps: vps, name: 'lxc')
    impermanence_feature = VpsFeature.find_by!(vps: vps, name: 'impermanence')
    feature_confirmations = confirmations_for(chain).select do |row|
      row.class_name == 'VpsFeature' && row.attr_changes.is_a?(Hash)
    end

    expect(created_vps).to eq(vps)
    expect(classes.count(Transactions::Storage::CreateDataset)).to be >= 3
    expect(classes).to include(
      Transactions::UserNamespace::UseMap,
      Transactions::Vps::Create,
      Transactions::NetworkInterface::CreateVethRouted,
      Transactions::Vps::DnsResolver,
      Transactions::Vps::Resources,
      Transactions::Vps::Features,
      Transactions::Vps::Start
    )
    expect(classes.count(Transactions::NetworkInterface::AddRoute)).to eq(1)
    expect(classes).not_to include(
      Transactions::Vps::DeployUserData,
      Transactions::Vps::ApplyUserData,
      Transactions::Vps::DeployPublicKey
    )

    expect(vps.dataset_in_pool).not_to be_nil
    expect(vps.datasets.order(:name).pluck(:name)).to eq([vps.id.to_s, 'srv', 'var'])
    expect(vps.mounts.order(:dst).pluck(:dst)).to eq(['/srv', '/var'])
    expect(vps.network_interfaces.order(:id).pluck(:name)).to eq(['venet0'])
    expect(vps.ip_addresses.count).to eq(1)
    expect(vps.dns_resolver).to eq(SpecSeed.other_dns_resolver)
    expect(vps_resources).to include('cpu' => 2, 'memory' => 2048, 'swap' => 0)
    expect(diskspace_use.value).to eq(10_240)
    expect(VpsFeature.where(vps: vps).count).to eq(
      VpsFeature::FEATURES.values.count { |feature| feature.support?(vps.node) }
    )
    expect(feature_confirmations.any? do |row|
      row.row_pks == { 'id' => lxc_feature.id } && row.attr_changes['enabled'] == 1
    end).to be(true)
    expect(feature_confirmations.any? do |row|
      row.row_pks == { 'id' => impermanence_feature.id } && row.attr_changes['enabled'] == 1
    end).to be(true)
    expect(VpsMaintenanceWindow.where(vps: vps).count).to eq(7)

    dataset_idx = classes.index(Transactions::Storage::CreateDataset)
    create_idx = classes.index(Transactions::Vps::Create)
    feature_idx = classes.index(Transactions::Vps::Features)
    resource_idx = classes.index(Transactions::Vps::Resources)
    start_idx = classes.index(Transactions::Vps::Start)

    expect(dataset_idx).to be < create_idx
    expect(create_idx).to be < feature_idx
    expect(feature_idx).to be < resource_idx
    expect(resource_idx).to be < start_idx
  end

  it 'deploys auto-add public keys and user data, then starts to apply NixOS user data even when start is false' do
    template = create_os_template!(
      distribution: 'nixos',
      manage_dns_resolver: false,
      config: { 'datasets' => [{ 'name' => '/' }] }
    )
    _pool, vps = build_create_vps(os_template: template, hostname: 'vps-create-user-data')
    key = create_user_public_key!(
      user: user,
      key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINixoscreate create@test',
      auto_add: true
    )
    user_data = create_vps_user_data!(
      user: user,
      format: 'nixos_configuration',
      content: '{ config, pkgs, ... }: { }'
    )

    chain, = described_class.fire(
      vps,
      ipv4: 0,
      ipv4_private: 0,
      ipv6: 0,
      start: false,
      vps_user_data: user_data
    )

    classes = tx_classes(chain)

    expect(classes).to include(
      Transactions::Vps::DeployPublicKey,
      Transactions::Vps::DeployUserData,
      Transactions::Vps::Start,
      Transactions::Vps::ApplyUserData
    )
    expect(tx_payload(chain, Transactions::Vps::DeployPublicKey)).to include('pubkey' => key.key)
    expect(tx_payload(chain, Transactions::Vps::DeployUserData)).to include(
      'format' => 'nixos_configuration'
    )
    expect(tx_payload(chain, Transactions::Vps::ApplyUserData)).to include(
      'format' => 'nixos_configuration'
    )
    expect(classes.index(Transactions::Vps::DeployPublicKey)).to be < classes.index(Transactions::Vps::Start)
    expect(classes.index(Transactions::Vps::DeployUserData)).to be < classes.index(Transactions::Vps::Start)
    expect(classes.index(Transactions::Vps::Start)).to be < classes.index(Transactions::Vps::ApplyUserData)
  end

  it 'does not start when start is false and user data does not require apply' do
    template = create_os_template!(
      manage_dns_resolver: false,
      config: { 'datasets' => [{ 'name' => '/' }] }
    )
    _pool, vps = build_create_vps(os_template: template, hostname: 'vps-create-no-start')
    user_data = create_vps_user_data!(
      user: user,
      format: 'script',
      content: "#!/bin/sh\necho spec\n"
    )

    chain, = described_class.fire(
      vps,
      ipv4: 0,
      ipv4_private: 0,
      ipv6: 0,
      start: false,
      vps_user_data: user_data
    )

    expect(tx_classes(chain)).to include(Transactions::Vps::DeployUserData)
    expect(tx_classes(chain)).not_to include(
      Transactions::Vps::Start,
      Transactions::Vps::ApplyUserData
    )
  end

  it 'raises when a template mount references a missing dataset' do
    template = create_os_template!(
      config: {
        'datasets' => [{ 'name' => '/' }],
        'mounts' => [{ 'dataset' => 'missing', 'mountpoint' => '/mnt/missing' }]
      }
    )
    _pool, vps = build_create_vps(os_template: template, hostname: 'vps-create-invalid-template')

    expect do
      described_class.fire(
        vps,
        ipv4: 0,
        ipv4_private: 0,
        ipv6: 0,
        start: false,
        vps_user_data: nil
      )
    end.to raise_error(RuntimeError, /dataset not found/)
  end
end
