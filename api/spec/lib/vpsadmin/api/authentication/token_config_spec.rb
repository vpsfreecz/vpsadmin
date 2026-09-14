# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::TokenConfig do
  let(:config) { described_class.new(nil, nil) }
  let(:user) { SpecSeed.user }
  let(:delivered_mail) { {} }
  let(:request) { build_request(user_agent: 'RSpec/TokenConfig') }

  before do
    user.reload
    SpecSeed.set_password!(user, 'secret')
    user.update!(
      enable_token_auth: true,
      enable_multi_factor_auth: false,
      enable_new_login_notification: false,
      password_reset: false,
      lockout: false
    )
    resolver = instance_double(Resolv, getname: 'ptr.example.test')
    allow(Resolv).to receive(:new).and_return(resolver)
  end

  def request_token(password: 'secret', auth_request: request, scope: 'all')
    described_class.request.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request: auth_request,
        input: {
          user: user.login,
          password:,
          lifetime: 'fixed',
          interval: 3600,
          scope:
        }
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )
  end

  def expect_empty_user_agent_session(session)
    expect(session.client_version).to eq('')
    expect(session.label).to eq('')
    expect(session.user_agent.agent).to eq('')
  end

  def reset_password(token, new_password1: 'new-secret', new_password2: 'new-secret')
    described_class.actions.fetch(:reset_password).handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        input: {
          token:,
          new_password1:,
          new_password2:
        }
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )
  end

  def complete_totp(token, code)
    described_class.actions.fetch(:totp).handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        input: {
          token:,
          code:
        }
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )
  end

  context 'with new-device email verification' do
    before do
      user.update!(enable_new_device_email_verification: true, email: 'member@example.test')
      create_user_device!(user:, known: true)
      allow(VpsAdmin::API::EmailLogin).to receive(:deliver!) { |_pending, code, _request| delivered_mail[:code] = code }
    end

    def email_action(token, action: :email_code, code: delivered_mail[:code])
      described_class.actions.fetch(action).handle.call(
        HaveAPI::Authentication::Token::ActionRequest.new(request:, input: { token:, code: }),
        HaveAPI::Authentication::Token::ActionResult.new
      )
    end

    it 'issues the requested scope only after a late email verification' do
      now = Time.current.change(usec: 0)
      allow(Time).to receive(:now).and_return(now)
      pending = request_token(scope: 'user#show user#index')
      expect(pending).to be_ok
      expect(pending).not_to be_complete
      expect(pending.next_action).to eq(:email_code)
      expect(pending.valid_to).to eq(now + 30.minutes)
      expect(UserSession.where(user:)).to be_empty
      allow(Time).to receive(:now).and_return(now + 29.minutes)
      result = email_action(pending.token)
      expect(result).to be_ok
      expect(result).to be_complete
      session = UserSession.joins(:token).find_by!(tokens: { token: result.token })
      expect(session.scope).to eq(%w[user#show user#index])
      expect(session.token.valid_to).to eq(now + 29.minutes + 3600)
      expect(email_action(pending.token)).not_to be_ok
    end

    it 'does not send a code for an incorrect password' do
      expect(VpsAdmin::API::EmailLogin).not_to receive(:deliver!) # rubocop:disable RSpec/MessageSpies
      expect(request_token(password: 'wrong')).not_to be_ok
      expect(user.auth_tokens).to be_empty
    end

    it 'keeps resend pending before a forced reset and grants a fresh reset interval' do
      user.update!(password_reset: true)
      allow(TransactionChains::User::PasswordChanged).to receive(:fire)
      now = Time.current.change(usec: 0)
      allow(Time).to receive(:now).and_return(now)
      pending = request_token
      allow(Time).to receive(:now).and_return(now + 29.minutes)
      resent = email_action(pending.token, action: :email_resend)
      expect(resent.next_action).to eq(:email_code)
      verified = email_action(pending.token)
      expect(verified.next_action).to eq(:reset_password)
      expect(verified.valid_to).to eq(now + 34.minutes)
      allow(Time).to receive(:now).and_return(now + 31.minutes)
      expect(reset_password(verified.token)).to be_complete
    end

    it 'accepts a TOTP recovery code without adding an email step' do
      user.update!(enable_multi_factor_auth: true)
      create_totp_device!(user:, recovery_code: 'recovery-code')
      allow(TransactionChains::User::TotpRecoveryCodeUsed).to receive(:fire)
      expect(VpsAdmin::API::EmailLogin).not_to receive(:deliver!) # rubocop:disable RSpec/MessageSpies
      pending = request_token
      expect(pending.next_action).to eq(:totp)
      expect(complete_totp(pending.token, 'recovery-code')).to be_complete
    end

    it 'preserves MFA proof through a forced reset after a recovery code' do
      user.update!(enable_multi_factor_auth: true, password_reset: true)
      create_totp_device!(user:, recovery_code: 'recovery-code')
      allow(TransactionChains::User::TotpRecoveryCodeUsed).to receive(:fire)
      allow(TransactionChains::User::PasswordChanged).to receive(:fire)
      expect(VpsAdmin::API::EmailLogin).not_to receive(:deliver!) # rubocop:disable RSpec/MessageSpies
      pending = request_token
      verified = complete_totp(pending.token, 'recovery-code')
      expect(verified.next_action).to eq(:reset_password)
      expect(reset_password(verified.token)).to be_complete
    end
  end

  it 'finds a user only for a valid open token session with token auth enabled' do
    session = create_open_session!(user:, auth_type: 'token')
    token = session.token.token

    expect(config.find_user_by_token(request, token)).to eq(user)
    expect(config.find_user_by_token(request, 'missing')).to be_nil

    session.close!
    expect(config.find_user_by_token(request, token)).to be_nil

    disabled = create_open_session!(user:, auth_type: 'token')
    user.update!(enable_token_auth: false)
    expect(config.find_user_by_token(request, disabled.token.token)).to be_nil
  end

  it 'returns a reset-password continuation instead of a session' do
    user.update!(password_reset: true)

    result = request_token

    expect(result).to be_ok
    expect(result).not_to be_complete
    expect(result.next_action).to eq(:reset_password)
    expect(result.token).to be_present
    expect(UserSession.where(user:, auth_type: 'token').count).to eq(0)

    auth_token = AuthToken.joins(:token).find_by!(tokens: { token: result.token })
    expect(auth_token).to be_reset_password
    expect(auth_token.opts).to include(
      'lifetime' => 'fixed',
      'interval' => 3600,
      'scope' => ['all']
    )
  end

  it 'preserves long token scopes through multi-factor authentication' do
    scopes = %w[
      token#revoke
      node#index
      node#show
      node_kernel_evidence#index
      node_kernel_evidence#show
      node_cgroup_state#index
      node_kernel_event#index
      node_kernel_configuration_option#index
      node_kernel_parameter#index
      node_kernel_module#index
      node_sysctl#index
      node_software_version#index
    ]
    user.update!(enable_multi_factor_auth: true)
    device = create_totp_device!(user:)
    now = Time.now.change(usec: 0)
    allow(Time).to receive(:now).and_return(now)

    continuation = request_token(scope: scopes.join(' '))

    expect(continuation).to be_ok
    expect(continuation).not_to be_complete
    expect(continuation.next_action).to eq(:totp)

    auth_token = AuthToken.joins(:token).find_by!(tokens: { token: continuation.token })
    expect(auth_token.opts['scope']).to eq(scopes)

    result = complete_totp(continuation.token, device.totp.at(now))

    expect(result).to be_ok
    expect(result).to be_complete
    expect(AuthToken.exists?(auth_token.id)).to be(false)

    session = UserSession.joins(:token).find_by!(tokens: { token: result.token })
    expect(session.scope).to eq(scopes)
  end

  it 'creates token sessions without a user agent header' do
    [nil, ''].each do |user_agent|
      result = request_token(auth_request: build_request(user_agent:))

      expect(result).to be_ok
      expect(result).to be_complete

      session = UserSession.joins(:token).find_by!(tokens: { token: result.token })
      expect(session.auth_type).to eq('token')
      expect_empty_user_agent_session(session)
    end
  end

  it 'rejects password-only issuance after a concurrent password change' do
    allow(VpsAdmin::API::Operations::Authentication::Password)
      .to receive(:run).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs)
        concurrent_user = User.find(user.id)
        concurrent_user.set_password('concurrent-secret')
        concurrent_user.save!
        result
      end

    expect do
      request_token
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'authentication expired'
    )

    expect(UserSession.where(user:, auth_type: 'token')).to be_empty
  end

  it 'rejects TOTP issuance after a concurrent password change' do
    user.update!(enable_multi_factor_auth: true)
    device = create_totp_device!(user:)
    now = Time.now.change(usec: 0)
    allow(Time).to receive(:now).and_return(now)
    continuation = request_token

    allow(VpsAdmin::API::Operations::Authentication::Totp)
      .to receive(:run).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs)
        concurrent_user = User.find(user.id)
        concurrent_user.set_password('concurrent-secret')
        concurrent_user.save!
        result
      end

    expect do
      complete_totp(continuation.token, device.totp.at(now))
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'authentication expired'
    )

    expect(UserSession.where(user:, auth_type: 'token')).to be_empty
  end

  it 'does not report a stale recovery code as used' do
    user.update!(enable_multi_factor_auth: true)
    device = create_totp_device!(user:, recovery_code: 'recovery-code')
    continuation = request_token
    op = VpsAdmin::API::Operations::Authentication::Totp.new
    lookups = 0
    allow(VpsAdmin::API::Operations::Authentication::Totp).to receive(:new).and_return(op)
    allow(op).to receive(:find_auth_token).and_wrap_original do |original, token|
      found = original.call(token)
      lookups += 1

      if lookups == 1
        concurrent_user = User.find(user.id)
        concurrent_user.set_password('concurrent-secret')
        concurrent_user.save!
      end

      found
    end
    allow(TransactionChains::User::TotpRecoveryCodeUsed).to receive(:fire)

    expect do
      complete_totp(continuation.token, 'recovery-code')
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')

    expect(device.reload.enabled).to be(true)
    expect(TransactionChains::User::TotpRecoveryCodeUsed).not_to have_received(:fire)
  end

  it 'uses the shared password minimum in token reset validation and errors' do
    stub_const('VpsAdmin::API::PasswordChanges::MINIMUM_LENGTH', 9)
    user.update!(password_reset: true)
    allow(TransactionChains::User::PasswordChanged).to receive(:fire)
    auth_token = create_auth_token!(user:, purpose: 'reset_password')

    result = reset_password(auth_token.to_s, new_password1: 'x' * 8, new_password2: 'x' * 8)
    expect(result.error).to eq('password should have at least 9 characters')
    expect(user.reload.password_reset).to be(true)

    result = reset_password(auth_token.to_s, new_password1: 'x' * 9, new_password2: 'x' * 9)
    expect(result).to be_ok
    expect(result).to be_complete
    expect(user.reload.password_reset).to be(false)
  end

  it 'can complete the reset-password continuation and create a token session' do
    user.update!(password_reset: true, lockout: true)
    allow(TransactionChains::User::PasswordChanged).to receive(:fire)
    auth_token = create_auth_token!(
      user:,
      purpose: 'reset_password',
      opts: {
        'lifetime' => 'fixed',
        'interval' => 3600,
        'scope' => ['all']
      }
    )

    result = reset_password(auth_token.to_s)

    expect(result).to be_ok
    expect(result).to be_complete
    expect(result.token).to be_present
    expect(AuthToken.exists?(auth_token.id)).to be(false)

    session = UserSession.joins(:token).find_by!(tokens: { token: result.token })
    expect(session.user).to eq(user)
    expect(session.auth_type).to eq('token')
    expect(PasswordChangeLog.find_by!(user:, source: 'forced_reset')).to have_attributes(
      user_session_id: session.id,
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'ptr.example.test'
    )
    expect(
      PasswordChangeLog.find_by!(user:, source: 'forced_reset').user_agent.agent
    ).to eq('RSpec/TokenConfig')
    expect(user.reload.password_reset).to be(false)
    expect(user.lockout).to be(false)
    expect(TransactionChains::User::PasswordChanged)
      .to have_received(:fire).with(user, request)
  end

  it 'rejects reset-token issuance after another password change' do
    user.update!(password_reset: true, lockout: true)
    allow(TransactionChains::User::PasswordChanged).to receive(:fire)
    auth_token = create_auth_token!(
      user:,
      purpose: 'reset_password',
      opts: {
        'lifetime' => 'fixed',
        'interval' => 3600,
        'scope' => ['all']
      }
    )

    allow(VpsAdmin::API::Operations::Authentication::ResetPassword)
      .to receive(:run).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs)
        concurrent_user = User.find(user.id)
        concurrent_user.set_password('concurrent-secret')
        concurrent_user.save!
        result
      end

    expect do
      reset_password(auth_token.to_s)
    end.to raise_error(
      VpsAdmin::API::Exceptions::AuthenticationError,
      'authentication expired'
    )

    expect(UserSession.where(user:, auth_type: 'token')).to be_empty
  end

  it 'renews renewable tokens through the provider action handler' do
    session = create_open_session!(
      user:,
      auth_type: 'token',
      token_lifetime: 'renewable_manual',
      token_interval: 3600,
      valid_to: 1.minute.from_now
    )
    old_valid_to = session.token.valid_to

    result = described_class.renew.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        user:,
        token: session.token.token
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )

    expect(result).to be_ok
    expect(result.valid_to).to be > old_valid_to
    expect(session.reload.token.valid_to).to eq(result.valid_to)
  end

  it 'revokes token sessions through the provider action handler' do
    session = create_open_session!(user:, auth_type: 'token')

    result = described_class.revoke.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        user:,
        token: session.token.token
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )

    expect(result).to be_ok
    expect(session.reload.closed_at).not_to be_nil
    expect(session.token).to be_nil
  end
end
