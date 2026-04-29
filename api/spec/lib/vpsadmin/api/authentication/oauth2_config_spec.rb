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
    expect(result.errors).to include('passwords do not match')
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

  it 'finds users by access token only when OAuth2 auth is enabled' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    token = session.token.token

    expect(config.find_user_by_access_token(request, token)).to eq(user)

    user.update!(enable_oauth2_auth: false)
    expect(config.find_user_by_access_token(request, token)).to be_nil
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
    expect(response.cookies).to have_key(described_class::SSO_COOKIE)
    expect(response.cookies).to have_key(described_class::DEVICES_COOKIE)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
