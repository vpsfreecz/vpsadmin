# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::Basic do
  let(:provider) { described_class.new(nil, nil) }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.70', user_agent: 'RSpec/Basic') }

  before do
    user.reload
    SpecSeed.set_password!(user, 'secret')
    user.update!(
      enable_basic_auth: true,
      enable_multi_factor_auth: false,
      password_reset: false,
      lockout: false
    )
    resolver = instance_double(Resolv, getname: 'ptr.example.test')
    allow(Resolv).to receive(:new).and_return(resolver)
  end

  it 'returns nil for an invalid password and records a failed login' do
    expect do
      expect(provider.send(:find_user, request, user.login, 'wrong')).to be_nil
    end.to change(UserFailedLogin, :count).by(1)

    expect(UserFailedLogin.order(:id).last.reason).to eq('invalid password')
  end

  it 'raises when password auth requires MFA' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    expect do
      provider.send(:find_user, request, user.login, 'secret')
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'multi-factor authentication required, use token auth instead'
    )
  end

  it 'raises when basic auth is disabled' do
    user.update!(enable_basic_auth: false)

    expect do
      provider.send(:find_user, request, user.login, 'secret')
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'HTTP basic authentication is disabled on this account'
    )
  end

  it 'returns the user and creates a closed basic session on success' do
    result = provider.send(:find_user, request, user.login, 'secret')

    expect(result).to eq(user)
    session = UserSession.order(:id).last
    expect(session.user).to eq(user)
    expect(session.auth_type).to eq('basic')
    expect(session.closed_at).not_to be_nil
    expect(session.token).to be_nil
  end
end
