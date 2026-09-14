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

  it 'records client metadata when upgrading a password hash before creating the session' do
    request.env['HTTP_X_REAL_IP'] = '192.0.2.43'
    request.env['HTTP_CLIENT_IP'] = '203.0.113.43'
    user.update_columns(
      password_version: 'md5',
      password: VpsAdmin::API::CryptoProviders::Md5.encrypt(user.login, 'secret')
    )

    expect do
      expect(provider.send(:find_user, request, user.login, 'secret')).to eq(user)
    end.to change(PasswordChangeLog, :count).by(1)

    event = PasswordChangeLog.order(:id).last
    expect(user.reload.password_version).to eq('bcrypt')
    expect(event).to have_attributes(
      source: 'other',
      user_session_id: nil,
      client_ip_addr: '192.0.2.43',
      client_ip_ptr: 'ptr.example.test'
    )
    expect(event.user_agent.agent).to eq('RSpec/Basic')
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

  it 'rejects email-protected password authentication without sending mail' do
    user.update!(enable_new_device_email_verification: true)
    create_user_device!(user:, known: true)
    expect(VpsAdmin::API::EmailLogin).not_to receive(:deliver!) # rubocop:disable RSpec/MessageSpies
    expect { provider.send(:find_user, request, user.login, 'secret') }
      .to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, /email verification required/)
    expect(UserSession.where(user:, auth_type: 'basic')).to be_empty
  end

  it 'raises when password reset is required' do
    user.update!(password_reset: true)

    expect do
      provider.send(:find_user, request, user.login, 'secret')
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'password reset required'
    )

    expect(UserSession.where(user:, auth_type: 'basic').count).to eq(0)
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

  it 'creates basic sessions without a user agent header' do
    [nil, ''].each do |user_agent|
      auth_request = build_request(ip: '198.51.100.70', user_agent:)
      result = provider.send(:find_user, auth_request, user.login, 'secret')

      expect(result).to eq(user)

      session = UserSession.order(:id).last
      expect(session.auth_type).to eq('basic')
      expect(session.client_version).to eq('')
      expect(session.label).to eq('')
      expect(session.user_agent.agent).to eq('')
    end
  end

  it 'rejects the request when the password changes after verification' do
    allow(VpsAdmin::API::Operations::Authentication::Password)
      .to receive(:run).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs)
        concurrent_user = User.find(user.id)
        concurrent_user.set_password('concurrent-secret')
        concurrent_user.save!
        result
      end

    expect do
      provider.send(:find_user, request, user.login, 'secret')
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'authentication expired'
    )

    expect(UserSession.where(user:, auth_type: 'basic')).to be_empty
  end
end
