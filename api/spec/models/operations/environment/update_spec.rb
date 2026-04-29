# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Environment::Update do
  let(:environment) { SpecSeed.environment }

  before do
    environment.update!(
      can_create_vps: false,
      can_destroy_vps: false,
      vps_lifetime: 7,
      max_vps_count: 1
    )
  end

  it 'updates the environment' do
    result = described_class.run(
      environment,
      {
        can_create_vps: true,
        can_destroy_vps: true,
        vps_lifetime: 30,
        max_vps_count: 3
      }
    )

    expect(result).to eq(environment)
    expect(environment.reload.can_create_vps).to be(true)
    expect(environment.can_destroy_vps).to be(true)
    expect(environment.vps_lifetime).to eq(30)
    expect(environment.max_vps_count).to eq(3)
  end

  it 'updates only default user configs when environment defaults change' do
    default_cfg = create_environment_user_config!(
      environment: environment,
      user: SpecSeed.user,
      default: true,
      attrs: {
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 7,
        max_vps_count: 1
      }
    )
    custom_cfg = create_environment_user_config!(
      environment: environment,
      user: SpecSeed.other_user,
      default: false,
      attrs: {
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 99,
        max_vps_count: 99
      }
    )

    described_class.run(
      environment,
      {
        can_create_vps: true,
        can_destroy_vps: true,
        vps_lifetime: 30,
        max_vps_count: 3
      }
    )

    expect(default_cfg.reload.can_create_vps).to be(true)
    expect(default_cfg.can_destroy_vps).to be(true)
    expect(default_cfg.vps_lifetime).to eq(30)
    expect(default_cfg.max_vps_count).to eq(3)

    expect(custom_cfg.reload.can_create_vps).to be(false)
    expect(custom_cfg.can_destroy_vps).to be(false)
    expect(custom_cfg.vps_lifetime).to eq(99)
    expect(custom_cfg.max_vps_count).to eq(99)
  end

  it 'wraps the environment update and default propagation in a transaction' do
    allow(Environment).to receive(:transaction).and_call_original

    described_class.run(environment, { can_create_vps: true })

    expect(Environment).to have_received(:transaction)
  end
end
