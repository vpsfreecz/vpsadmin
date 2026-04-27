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

  it 'clears ownership and chains host address cleanup' do
    ensure_available_node_status!(SpecSeed.node)
    ip = create_owned_ip
    host_ip = ip.host_ip_addresses.take!
    host_ip.update!(user_created: true)
    before_old = resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)

    chain, = described_class.fire(ip, user: nil)

    expect(ip.reload.user_id).to be_nil
    expect(ip.charged_environment_id).to be_nil
    expect(resource_use_value(user: SpecSeed.user, environment: SpecSeed.environment, resource: :ipv4)).to eq(
      before_old - 1
    )
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'HostIpAddress' && row.row_pks == { 'id' => host_ip.id } }
        .confirm_type
    ).to eq('just_destroy_type')
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
