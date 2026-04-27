# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::Create do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    ensure_user_namespace_blocks!(count: 12)
    seed_pool_dataset_properties!(create_pool!(node: SpecSeed.node, role: :primary))
    create_default_package!(environment: SpecSeed.environment)
  end

  def build_user(login: "create-user-#{SecureRandom.hex(4)}")
    User.new(
      login: login,
      full_name: 'Spec Create User',
      email: "#{login}@test.invalid",
      level: 1,
      language: SpecSeed.language,
      enable_basic_auth: true,
      enable_token_auth: true,
      mailer_enabled: true
    ).tap { |user| user.set_password('secret123') }
  end

  def create_default_package!(environment:)
    pkg = ClusterResourcePackage.create!(label: "Default #{SecureRandom.hex(4)}")
    {
      cpu: 4,
      memory: 256 * 1024,
      swap: 256 * 1024,
      diskspace: 300 * 1024
    }.each do |resource, value|
      ClusterResourcePackageItem.create!(
        cluster_resource_package: pkg,
        cluster_resource: ClusterResource.find_by!(name: resource.to_s),
        value: value
      )
    end
    DefaultUserClusterResourcePackage.create!(
      environment: environment,
      cluster_resource_package: pkg
    )
    pkg
  end

  it 'creates user infrastructure, links default packages, confirms rows, and sends welcome mail' do
    default_pkg = create_default_package!(environment: SpecSeed.environment)
    user = build_user

    chain, created = described_class.fire(user, false, nil, nil, true)

    expect(created).to be_persisted
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(EnvironmentUserConfig.where(user: created).count).to eq(Environment.count)
    expect(UserClusterResource.where(user: created).count).to eq(
      Environment.count * ClusterResource.count
    )

    personal_pkgs = ClusterResourcePackage.where(user: created, label: 'Personal package')
    expect(personal_pkgs.count).to eq(Environment.count)
    expect(ClusterResourcePackageItem.where(cluster_resource_package: personal_pkgs).count).to eq(
      Environment.count * ClusterResource.count
    )
    expect(UserClusterResourcePackage.exists?(
             user: created,
             environment: SpecSeed.environment,
             cluster_resource_package: default_pkg
           )).to be(true)

    confirmation_models = confirmations_for(chain).map(&:class_name)
    expect(confirmation_models).to include(
      'User',
      'EnvironmentUserConfig',
      'UserClusterResource',
      'ClusterResourcePackage',
      'ClusterResourcePackageItem',
      'UserClusterResourcePackage'
    )
  end

  it 'records inactive user creation as suspended' do
    user = build_user

    chain, created = described_class.fire(user, false, nil, nil, false)

    expect(created.object_state).to eq('suspended')
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'User' &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['object_state'] == User.object_states[:suspended]
    end).to be(true)
  end

  it 'passes the initial VPS start flag from activation state' do
    user = build_user
    calls = []

    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:use_chain).and_wrap_original do |method, chain_class, opts|
      if chain_class == TransactionChains::Vps::Create
        calls << [chain_class, opts]
        nil
      else
        method.call(chain_class, opts)
      end
    end
    # rubocop:enable RSpec/AnyInstance

    described_class.fire(user, true, SpecSeed.node, SpecSeed.os_template, false)

    expect(calls.size).to eq(1)
    chain_class, opts = calls.first
    vps, vps_opts = opts.fetch(:args)
    expect(chain_class).to eq(TransactionChains::Vps::Create)
    expect(vps).to be_a(Vps)
    expect(vps.user).to eq(user)
    expect(vps.node).to eq(SpecSeed.node)
    expect(vps.os_template).to eq(SpecSeed.os_template)
    expect(vps_opts).to include(start: false)
  end
end
