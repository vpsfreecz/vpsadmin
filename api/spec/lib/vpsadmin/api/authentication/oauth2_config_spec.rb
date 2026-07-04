# frozen_string_literal: true

require 'spec_helper'

module OAuth2ConfigSpecFixtures
  class FakeOAuth2Request
    attr_reader :client_id, :response_type, :redirect_uri, :scope, :state,
                :code_challenge, :code_challenge_method

    def initialize(client_id:, response_type:, redirect_uri:, scope:, state: nil,
                   code_challenge: nil, code_challenge_method: nil)
      @client_id = client_id
      @response_type = response_type
      @redirect_uri = redirect_uri
      @scope = scope
      @state = state
      @code_challenge = code_challenge
      @code_challenge_method = code_challenge_method
    end
  end

  class FakeOAuth2Response
    attr_reader :body, :cookies
    attr_accessor :content_type

    def initialize
      @body = +''
      @cookies = {}
    end

    def write(str)
      @body << str
    end

    def set_cookie(name, value)
      @cookies[name] = value
    end
  end

  class FakeSinatraHandler
    attr_reader :cookies

    def initialize(cookies = {})
      @cookies = cookies
    end
  end

  class Provider
    def authorize_path
      '/_auth/oauth2/authorize'
    end
  end
end

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe VpsAdmin::API::Authentication::OAuth2Config do
  let(:provider) { OAuth2ConfigSpecFixtures::Provider.new }
  let(:config) { described_class.new(provider, nil, nil) }
  let(:user) { SpecSeed.user }
  let(:client) { create_oauth2_client!(issue_refresh_token: true, access_token_seconds: 900) }
  let(:request) { build_request(ip: '198.51.100.71', user_agent: 'RSpec/OAuth2') }
  let(:oauth2_request) do
    OAuth2ConfigSpecFixtures::FakeOAuth2Request.new(
      client_id: client.client_id,
      response_type: 'code',
      redirect_uri: client.redirect_uri,
      scope: ['all'],
      state: 'state-1'
    )
  end
  let(:response) { OAuth2ConfigSpecFixtures::FakeOAuth2Response.new }
  let(:handler) { OAuth2ConfigSpecFixtures::FakeSinatraHandler.new }

  before do
    user.reload
    SpecSeed.set_password!(user, 'secret')
    user.update!(
      enable_oauth2_auth: true,
      enable_single_sign_on: true,
      enable_multi_factor_auth: false,
      enable_new_login_notification: false,
      password_reset: false,
      lockout: false
    )
    resolver = instance_double(Resolv, getname: 'ptr.example.test')
    allow(Resolv).to receive(:new).and_return(resolver)
  end

  def create_webauthn_credential!(target_user)
    WebauthnCredential.create!(
      user: target_user,
      label: 'RSpec passkey',
      enabled: true,
      external_id: SecureRandom.hex(16),
      public_key: 'spec-public-key',
      sign_count: 0
    )
  end

  it 'renders the authorize page for a valid client' do
    result = config.handle_get_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {},
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result).to be_nil
    expect(response.content_type).to eq('text/html')
    expect(response.body).to include(client.name)
    expect(response.body).to include('Log in')
  end

  it 'uses ui_locales for the authorize page language' do
    result = config.handle_get_authorize(
      sinatra_handler: handler,
      sinatra_request: build_request(extra_env: {
        'HTTP_ACCEPT_LANGUAGE' => 'en-US,en;q=0.9'
      }),
      sinatra_params: {
        ui_locales: 'cs-CZ'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result).to be_nil
    expect(response.body).to include('<html lang="cs">')
    expect(response.body).to include('Přihlásit se pomocí vpsAdminu')
    expect(response.body).to include('value="Přihlásit se"')
    expect(response.body).to include('name="ui_locales" value="cs-CZ"')
  end

  it 'renders keyed auth errors in the requested authorize page language' do
    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_credentials: '1',
        user: 'missing-user',
        password: 'wrong-password',
        ui_locales: 'cs'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.errors).to include(:invalid_user_or_password)
    expect(response.body).to include('neplatný uživatel nebo heslo')
    expect(response.body).not_to include('invalid user or password')
  end

  it 'falls back to a readable auth error when a symbolic error has no translation' do
    expect(config.send(:translated_auth_errors, [:external_provider_error]))
      .to eq(['external provider error'])
  end

  it 're-renders the authorize page with an auth token when credentials require MFA' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_credentials: '1',
        user: user.login,
        password: 'secret'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(false)
    expect(result.auth_token).to be_mfa
    expect(response.body).to include(result.auth_token.to_s)
    expect(response.body).to include('TOTP code')
  end

  it 'renders passkey MFA without automatically starting WebAuthn' do
    create_webauthn_credential!(user)
    user.update!(enable_multi_factor_auth: true)

    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_credentials: '1',
        user: user.login,
        password: 'secret'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(false)
    expect(result.auth_token).to be_mfa
    expect(response.body).to include('Log in with a passkey')
    expect(response.body).to include('Ask again in a day')
    expect(response.body).to include('async function webAuthn(event)')
    expect(response.body).to include('onclick="webAuthn(event);"')
    expect(response.body).not_to include('webAuthn();')
    expect(response.body).not_to include('DOMContentLoaded')
  end

  it 'completes TOTP authentication and creates an authorization code' do
    device = create_totp_device!(user:)
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    t = Time.at(1_700_000_000)
    allow(Time).to receive(:now).and_return(t)

    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_totp: '1',
        auth_token: auth_token.to_s,
        totp_code: device.totp.at(t),
        next_multi_factor_auth: 'require'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(true)
    expect(result.authorization).to be_present
    expect(result.authorization.code).to be_present
    expect(config.get_authorization_code(result)).to eq(result.authorization.code.token)
    expect(AuthToken.exists?(auth_token.id)).to be(false)
  end

  it 'completes TOTP authentication with a recovery code and disables the device' do
    recovery_code = 'oauth2-recovery-code'
    device = create_totp_device!(user:, recovery_code:)
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    allow(TransactionChains::User::TotpRecoveryCodeUsed).to receive(:fire)

    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_totp: '1',
        auth_token: auth_token.to_s,
        totp_code: recovery_code,
        next_multi_factor_auth: 'require'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(true)
    expect(result.authorization).to be_present
    expect(device.reload.enabled).to be(false)
    expect(TransactionChains::User::TotpRecoveryCodeUsed)
      .to have_received(:fire).with(user, device, request)
  end

  it 're-renders the reset-password branch when passwords do not match' do
    auth_token = create_auth_token!(user:, purpose: 'reset_password')

    result = config.handle_post_authorize(
      sinatra_handler: handler,
      sinatra_request: request,
      sinatra_params: {
        login_reset_password: '1',
        auth_token: auth_token.to_s,
        new_password1: 'new-password-1',
        new_password2: 'new-password-2'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(false)
    expect(result).to be_reset_password
    expect(result.errors).to include(:passwords_do_not_match)
    expect(response.body).to include('passwords do not match')
  end

  it 'creates a user session, destroys the auth code, and returns access and refresh tokens' do
    authorization = create_oauth2_authorization!(user:, client:)
    code_id = authorization.code.id

    access_token, valid_to, refresh_token = config.get_tokens(authorization, request)

    authorization.reload
    expect(authorization.user_session).to be_present
    expect(authorization.code).to be_nil
    expect(Token.exists?(code_id)).to be(false)
    expect(access_token).to eq(authorization.user_session.token.token)
    expect(valid_to).to eq(authorization.user_session.token.valid_to)
    expect(refresh_token).to eq(authorization.refresh_token.token)
  end

  it 'creates OAuth2 token sessions without a user agent header' do
    [nil, ''].each do |user_agent|
      authorization = create_oauth2_authorization!(user:, client:)
      auth_request = build_request(ip: '198.51.100.71', user_agent:)

      access_token, = config.get_tokens(authorization, auth_request)

      session = authorization.reload.user_session
      expect(session).to be_present
      expect(session.auth_type).to eq('oauth2')
      expect(access_token).to eq(session.token.token)
      expect(session.client_version).to eq('')
      expect(session.label).to eq('')
      expect(session.user_agent.agent).to eq('')
    end
  end

  it 'does not find expired authorization codes' do
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      code_valid_to: 1.minute.ago
    )

    expect(config.find_authorization_by_code(client, authorization.code.token)).to be_nil
  end

  it 'does not find authorization codes for locked or forced-reset users' do
    %i[lockout password_reset].each do |flag|
      user.update!(lockout: false, password_reset: false)
      authorization = create_oauth2_authorization!(user:, client:)
      code = authorization.code.token
      user.update!(flag => true)

      expect(config.find_authorization_by_code(client, code)).to be_nil
    end
  end

  it 'refreshes tokens by replacing the access token and refresh token' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      user_session: session,
      refresh_valid_to: 1.hour.from_now
    )
    old_access_id = session.token.id
    old_refresh_id = authorization.refresh_token.id

    access_token, _valid_to, refresh_token = config.refresh_tokens(authorization, request)

    expect(Token.exists?(old_access_id)).to be(false)
    expect(Token.exists?(old_refresh_id)).to be(false)
    expect(session.reload.token.token).to eq(access_token)
    expect(authorization.reload.refresh_token.token).to eq(refresh_token)
  end

  it 'does not find refresh tokens for locked or forced-reset users' do
    %i[lockout password_reset].each do |flag|
      user.update!(lockout: false, password_reset: false)
      session = create_open_session!(user:, auth_type: 'oauth2')
      authorization = create_oauth2_authorization!(
        user:,
        client:,
        user_session: session,
        refresh_valid_to: 1.hour.from_now
      )
      refresh_token = authorization.refresh_token.token
      user.update!(flag => true)

      expect(config.find_authorization_by_refresh_token(client, refresh_token)).to be_nil
    end
  end

  it 'revokes access tokens only for the authenticated OAuth2 client' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    authorization = create_oauth2_authorization!(user:, client:, user_session: session)
    other_client = create_oauth2_client!
    token = session.token.token

    expect(config.handle_post_revoke(request, token, client: other_client)).to eq(:revoked)
    expect(session.reload.token.token).to eq(token)
    expect(authorization.reload.user_session.closed_at).to be_nil

    expect(config.handle_post_revoke(request, token, client:)).to eq(:revoked)
    expect(session.reload.token).to be_nil
    expect(session.closed_at).not_to be_nil
  end

  it 'revokes refresh tokens only for the authenticated OAuth2 client' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      user_session: session,
      refresh_valid_to: 1.hour.from_now
    )
    other_client = create_oauth2_client!
    token = authorization.refresh_token.token

    expect(config.handle_post_revoke(request, token, client: other_client)).to eq(:revoked)
    expect(authorization.reload.refresh_token.token).to eq(token)

    expect(config.handle_post_revoke(request, token, client:)).to eq(:revoked)
    expect(authorization.reload.refresh_token).to be_nil
    expect(session.reload.token).not_to be_nil
  end

  it 'rejects revoke handling without an authenticated OAuth2 client' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    token = session.token.token
    create_oauth2_authorization!(user:, client:, user_session: session)

    expect { config.handle_post_revoke(request, token) }
      .to raise_error(ArgumentError, 'OAuth2 revoke client is required')
    expect(session.reload.token.token).to eq(token)
  end

  it 'finds users by access token only when OAuth2 auth is enabled' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    token = session.token.token

    expect(config.find_user_by_access_token(request, token)).to eq(user)

    user.update!(enable_oauth2_auth: false)
    expect(config.find_user_by_access_token(request, token)).to be_nil
  end

  it 'does not authorize from SSO when password reset is pending' do
    client.update!(allow_single_sign_on: true)
    user.update!(password_reset: true)
    sso = create_single_sign_on!(user:)
    device = create_user_device!(user:, known: true)
    cookie_handler = OAuth2ConfigSpecFixtures::FakeSinatraHandler.new(
      described_class::SSO_COOKIE => sso.token.token,
      described_class::DEVICES_COOKIE => device.token.token
    )

    expect do
      config.handle_get_authorize(
        sinatra_handler: cookie_handler,
        sinatra_request: request,
        sinatra_params: {},
        oauth2_request:,
        oauth2_response: response,
        client:
      )
    end.not_to change(Oauth2Authorization, :count)

    expect(response.body).to include('password reset required')
  end

  it 'does not skip MFA on a remembered device when password reset is pending' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true, password_reset: true)
    device = create_user_device!(
      user:,
      known: true,
      skip_multi_factor_auth_until: 1.week.from_now,
      last_next_multi_factor_auth: 'week'
    )
    cookie_handler = OAuth2ConfigSpecFixtures::FakeSinatraHandler.new(
      described_class::DEVICES_COOKIE => device.token.token
    )

    result = config.handle_post_authorize(
      sinatra_handler: cookie_handler,
      sinatra_request: request,
      sinatra_params: {
        login_credentials: '1',
        user: user.login,
        password: 'secret'
      },
      oauth2_request:,
      oauth2_response: response,
      client:
    )

    expect(result.authenticated).to be(true)
    expect(result.complete).to be(false)
    expect(result.auth_token).to be_mfa
    expect(result.authorization).to be_nil
    expect(response.body).to include('TOTP code')
  end

  it 'rechecks login eligibility before TOTP completion creates an authorization' do
    device = create_totp_device!(user:)
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    t = Time.at(1_700_000_000)
    allow(Time).to receive(:now).and_return(t)
    user.update!(lockout: true)

    expect do
      result = config.handle_post_authorize(
        sinatra_handler: handler,
        sinatra_request: request,
        sinatra_params: {
          login_totp: '1',
          auth_token: auth_token.to_s,
          totp_code: device.totp.at(t),
          next_multi_factor_auth: 'require'
        },
        oauth2_request:,
        oauth2_response: response,
        client:
      )

      expect(result.authenticated).to be(true)
      expect(result.complete).to be(false)
      expect(result.authorization).to be_nil
      expect(result.errors).to include(:account_locked)
    end.not_to change(Oauth2Authorization, :count)
  end

  it 'rechecks OAuth2 enablement before reset completion creates an authorization' do
    user.update!(password_reset: true, enable_oauth2_auth: false)
    auth_token = create_auth_token!(user:, purpose: 'reset_password')

    expect do
      result = config.handle_post_authorize(
        sinatra_handler: handler,
        sinatra_request: request,
        sinatra_params: {
          login_reset_password: '1',
          auth_token: auth_token.to_s,
          new_password1: 'new-password',
          new_password2: 'new-password'
        },
        oauth2_request:,
        oauth2_response: response,
        client:
      )

      expect(result.authenticated).to be(true)
      expect(result.complete).to be(false)
      expect(result.authorization).to be_nil
      expect(result.errors).to include(:oauth2_disabled)
    end.not_to change(Oauth2Authorization, :count)
  end

  it 'creates authorization cookies and SSO metadata' do
    auth_result = described_class::AuthResult.new(
      authenticated: true,
      complete: true,
      user:
    )

    config.send(
      :create_authorization,
      auth_result:,
      sinatra_request: request,
      oauth2_request:,
      oauth2_response: response,
      client:,
      devices: []
    )

    authorization = auth_result.authorization
    expect(authorization).to be_present
    expect(authorization.code).to be_present
    expect(authorization.single_sign_on).to be_present
    expect(authorization.user_device).to be_present

    expect(response.cookies.fetch(described_class::SSO_COOKIE)).to include(
      value: authorization.single_sign_on.token.token,
      max_age: 24 * 60 * 60,
      httponly: true,
      secure: true,
      same_site: :lax
    )
    expect(response.cookies.fetch(described_class::DEVICES_COOKIE)).to include(
      value: authorization.user_device.token.token,
      max_age: UserDevice::LIFETIME,
      httponly: true,
      secure: true,
      same_site: :lax
    )
  end

  it 'records new-device authorization metadata from X-Real-IP' do
    spoofed_request = build_request(
      ip: '198.51.100.72',
      user_agent: 'RSpec/OAuth2',
      extra_env: {
        'HTTP_CLIENT_IP' => '203.0.113.72',
        'HTTP_X_REAL_IP' => '203.0.113.73'
      }
    )
    auth_result = described_class::AuthResult.new(
      authenticated: true,
      complete: true,
      user:
    )

    config.send(
      :create_authorization,
      auth_result:,
      sinatra_request: spoofed_request,
      oauth2_request:,
      oauth2_response: response,
      client:,
      devices: []
    )

    authorization = auth_result.authorization
    expect(authorization.client_ip_addr).to eq('203.0.113.73')
    expect(authorization.client_ip_addr).not_to eq('203.0.113.72')
    expect(authorization.client_ip_addr).not_to eq('198.51.100.72')
    expect(authorization.user_device.client_ip_addr).to eq('203.0.113.73')
  end

  it 'records known-device authorization metadata from X-Real-IP' do
    device = create_user_device!(user:, known: true)
    spoofed_request = build_request(
      ip: '198.51.100.74',
      user_agent: 'RSpec/OAuth2',
      extra_env: { 'HTTP_X_REAL_IP' => '203.0.113.74' }
    )
    auth_result = described_class::AuthResult.new(
      authenticated: true,
      complete: true,
      user:
    )

    config.send(
      :create_authorization,
      auth_result:,
      sinatra_request: spoofed_request,
      oauth2_request:,
      oauth2_response: response,
      client:,
      devices: [device]
    )

    authorization = auth_result.authorization
    expect(authorization.client_ip_addr).to eq('203.0.113.74')
    expect(authorization.client_ip_addr).not_to eq('198.51.100.74')
    expect(authorization.user_device).to eq(device)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
