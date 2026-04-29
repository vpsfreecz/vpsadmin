# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::Password do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) do
    build_request(
      ip: '198.51.100.42',
      user_agent: 'RSpec/Password',
      extra_env: { 'HTTP_X_REAL_IP' => '203.0.113.9' }
    )
  end

  before do
    SpecSeed.set_password!(user, 'secret')
    user.update!(
      enable_multi_factor_auth: false,
      password_reset: false,
      lockout: false,
      enable_basic_auth: true
    )
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'returns nil for an unknown login' do
    expect(op.run('missing-user', 'secret', request:)).to be_nil
  end

  it 'returns an unauthenticated result for a wrong password' do
    result = op.run(user.login, 'wrong', request:)

    expect(result).not_to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_nil
  end

  it 'returns a complete authenticated result for a correct password' do
    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).to be_complete
    expect(result.user).to eq(user)
    expect(result.token).to be_nil
  end

  it 'returns an MFA token when MFA is required and enabled' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_mfa
    expect(result.token.client_ip_addr).to eq('203.0.113.9')
  end

  it 'does not create an MFA token when multi-factor handling is disabled' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    result = op.run(user.login, 'secret', multi_factor: false, request:)

    expect(result).to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_nil
  end

  it 'returns a reset-password token when no MFA is required' do
    user.update!(password_reset: true)

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).to be_complete
    expect(result).to be_reset_password
    expect(result.token).to be_reset_password
  end

  it 'copies request metadata into created auth tokens' do
    user.update!(password_reset: true)

    token = op.run(user.login, 'secret', request:).token

    expect(token.api_ip_addr).to eq('198.51.100.42')
    expect(token.api_ip_ptr).to eq('ptr.example.test')
    expect(token.client_ip_addr).to eq('203.0.113.9')
    expect(token.client_ip_ptr).to eq('ptr.example.test')
    expect(token.user_agent.agent).to eq('RSpec/Password')
    expect(token.client_version).to eq('RSpec/Password')
  end

  it 'upgrades the password hash when an old provider matches' do
    user.update!(
      password_version: :md5,
      password: VpsAdmin::API::CryptoProviders::Md5.encrypt(user.login, 'secret')
    )

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(user.reload.password_version).to eq('bcrypt')
    expect(VpsAdmin::API::CryptoProviders::Bcrypt.matches?(user.password, user.login, 'secret')).to be(true)
  end
end
