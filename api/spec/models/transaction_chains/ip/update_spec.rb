# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Ip::Update do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def resource_use_value(user:, environment:, resource:)
    user_env = user.environment_user_configs.find_by!(environment: environment)

    ClusterResourceUse
      .joins(user_cluster_resource: :cluster_resource)
      .find_by(
        user_cluster_resources: {
          user_id: user.id,
          environment_id: environment.id
        },
        cluster_resources: { name: resource.to_s },
        class_name: 'EnvironmentUserConfig',
        row_id: user_env.id
      )&.value.to_i
  end

  def create_owned_ip(user: SpecSeed.user, location: SpecSeed.location)
    ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: location,
      user: user,
      addr: "192.0.2.#{120 + SecureRandom.random_number(50)}"
    )
    ip.update!(charged_environment: location.environment)
    ip
  end

  def create_primary_reference(ip, owner: ip.current_owner)
    zone = create_dns_zone!(user: owner, source: :external_source)
    create_dns_zone_transfer!(
      dns_zone: zone, host_ip_address: ip.host_ip_addresses.take!, peer_type: :primary_type
    )
  end

  it 'rejects changing a referenced detached owner before either quota is changed' do
    ip = create_owned_ip
    transfer = create_primary_reference(ip)
    quotas = [SpecSeed.user, SpecSeed.other_user].to_h do |owner|
      [owner.id, resource_use_value(user: owner, environment: SpecSeed.environment, resource: :ipv4)]
    end

    expect do
      described_class.fire(ip, user: SpecSeed.other_user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse)

    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
    expect(transfer.reload).to be_persisted
    quotas.each do |owner_id, value|
      expect(resource_use_value(user: User.find(owner_id), environment: SpecSeed.environment, resource: :ipv4))
        .to eq(value)
    end
    expect(ip).not_to be_locked
  end

  it 'keeps the same-owner no-op when the address has DNS references' do
    ip = create_owned_ip
    transfer = create_primary_reference(ip)
    chain, = described_class.fire(ip, user: SpecSeed.user, environment: SpecSeed.environment)

    expect(chain).to be_nil
    expect(transfer.reload).to be_persisted
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
  end

  it 'rolls back DNS cleanup preparation if disown accounting fails' do
    ensure_available_node_status!(SpecSeed.node)
    ip = create_owned_ip
    transfer = create_primary_reference(ip)
    create_dns_server_zone!(
      dns_zone: transfer.dns_zone, dns_server: create_dns_server!(node: SpecSeed.node), zone_type: :secondary_type
    )
    before = resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)
    allow_any_instance_of(EnvironmentUserConfig).to receive(:adjust_resource!).and_raise('accounting failure') # rubocop:disable RSpec/AnyInstance

    expect { described_class.fire(ip, user: nil) }.to raise_error(RuntimeError, 'accounting failure')

    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
    expect(transfer.reload.confirmed).to eq(:confirmed)
    expect(resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)).to eq(before)
    expect(ip).not_to be_locked
  end

  it 'allows claiming the same effective owner of an unowned assigned address' do
    fixture = create_netif_vps_fixture!(user: SpecSeed.user)
    SpecSeed.environment.update!(user_ip_ownership: false)
    ip = create_owned_ip(user: nil)
    ip.update!(network_interface: fixture[:netif])
    transfer = create_primary_reference(ip)

    described_class.fire(ip, user: SpecSeed.user, environment: SpecSeed.environment)

    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(transfer.reload).to be_persisted
  end

  it 'requires explicit reference removal when an unowned detached address has DNS transfers' do
    ip = create_owned_ip(user: nil)
    create_primary_reference(ip, owner: nil)

    expect do
      described_class.fire(ip, user: SpecSeed.other_user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInUse)
    expect(ip.reload.user_id).to be_nil
  end

  it 'rejects new or different ownership while allowing same-owner no-op and disownership' do
    ip = create_owned_ip
    ip.network.update!(enabled: false)
    expect do
      described_class.fire(ip, user: SpecSeed.other_user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled/)
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect { described_class.fire(ip, user: SpecSeed.user, environment: SpecSeed.environment) }.not_to raise_error
    expect { described_class.fire(ip, user: nil) }.not_to raise_error
    expect(ip.reload.user_id).to be_nil
    expect do
      described_class.fire(ip, user: SpecSeed.user, environment: SpecSeed.environment)
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled/)
  end

  it 'moves resource use from the old owner to the new owner' do
    ip = create_owned_ip
    before_old = resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)
    before_new = resource_use_value(user: SpecSeed.other_user, environment: SpecSeed.environment, resource: :ipv4)

    chain, = described_class.fire(
      ip,
      user: SpecSeed.other_user,
      environment: SpecSeed.environment
    )

    expect(chain).to be_nil
    expect(ip.reload.user_id).to eq(SpecSeed.other_user.id)
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
    expect(resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)).to eq(
      before_old - 1
    )
    expect(resource_use_value(user: SpecSeed.other_user, environment: SpecSeed.environment, resource: :ipv4)).to eq(
      before_new + 1
    )
  end

  it 'defers ownership and accounting until host cleanup succeeds' do
    ensure_available_node_status!(SpecSeed.node)
    ip = create_owned_ip
    host_ip = ip.host_ip_addresses.take!
    host_ip.update!(user_created: true)
    before_old = resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)

    chain, = described_class.fire(ip, user: nil)

    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(ip.charged_environment_id).to eq(SpecSeed.environment.id)
    expect(resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)).to eq(
      before_old
    )
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp, Transactions::Utils::NoOp])
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'HostIpAddress' && row.row_pks == { 'id' => host_ip.id } }
        .confirm_type
    ).to eq('just_destroy_type')
  end

  it 'disowns immediately when there is no asynchronous cleanup' do
    ip = create_owned_ip
    before = resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)
    chain, = described_class.fire(ip, user: nil)
    expect(chain).to be_nil
    expect(ip.reload.user_id).to be_nil
    expect(ip.charged_environment_id).to be_nil
    expect(resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)).to eq(before - 1)
  end

  it 'requires an environment when assigning an owner' do
    ip = create_owned_ip(user: nil)

    expect do
      described_class.fire(ip, user: SpecSeed.user)
    end.to raise_error(RuntimeError, /missing environment/)
  end

  it 'rejects assignment to a user outside the IP environment' do
    ip = create_owned_ip(user: nil)

    expect do
      described_class.fire(
        ip,
        user: SpecSeed.other_user,
        environment: SpecSeed.other_environment
      )
    end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalidLocation)
  end
end
