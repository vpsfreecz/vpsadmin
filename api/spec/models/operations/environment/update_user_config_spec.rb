# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Environment::UpdateUserConfig do
  let(:environment) { SpecSeed.environment }
  let(:user) { SpecSeed.user }

  before do
    environment.update!(
      can_create_vps: true,
      can_destroy_vps: true,
      vps_lifetime: 30,
      max_vps_count: 5
    )
  end

  it 'resets the row to environment defaults when default is requested' do
    cfg = create_environment_user_config!(
      environment: environment,
      user: user,
      default: false,
      attrs: {
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 99,
        max_vps_count: 99
      }
    )

    described_class.run(cfg, { default: true, max_vps_count: 1 })

    expect(cfg.reload.default).to be(true)
    expect(cfg.can_create_vps).to be(true)
    expect(cfg.can_destroy_vps).to be(true)
    expect(cfg.vps_lifetime).to eq(30)
    expect(cfg.max_vps_count).to eq(5)
  end

  it 'keeps overrides when default is false' do
    cfg = create_environment_user_config!(
      environment: environment,
      user: user,
      default: true
    )

    described_class.run(
      cfg,
      {
        default: false,
        can_create_vps: false,
        can_destroy_vps: false,
        vps_lifetime: 99,
        max_vps_count: 99
      }
    )

    expect(cfg.reload.default).to be(false)
    expect(cfg.can_create_vps).to be(false)
    expect(cfg.can_destroy_vps).to be(false)
    expect(cfg.vps_lifetime).to eq(99)
    expect(cfg.max_vps_count).to eq(99)
  end

  it 'returns the updated row' do
    cfg = create_environment_user_config!(
      environment: environment,
      user: user,
      default: true
    )

    result = described_class.run(cfg, { default: false, max_vps_count: 9 })

    expect(result).to eq(cfg)
    expect(result.reload.max_vps_count).to eq(9)
  end
end
