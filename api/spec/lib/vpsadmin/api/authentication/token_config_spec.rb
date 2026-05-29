# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::TokenConfig do
  let(:config) { described_class.new(nil, nil) }
  let(:user) { SpecSeed.user }
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
  end

  def request_token(password: 'secret', auth_request: request)
    described_class.request.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request: auth_request,
        input: {
          user: user.login,
          password:,
          lifetime: 'fixed',
          interval: 3600,
          scope: 'all'
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

  it 'can complete the reset-password continuation and create a token session' do
    user.update!(password_reset: true, lockout: true)
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
    expect(user.reload.password_reset).to be(false)
    expect(user.lockout).to be(false)
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
