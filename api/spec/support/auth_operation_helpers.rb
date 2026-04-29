# frozen_string_literal: true

require 'rack/mock'
require 'securerandom'

module AuthOperationHelpers
  def build_request(ip: '127.0.0.1', user_agent: 'RSpec auth', extra_env: {})
    env = Rack::MockRequest.env_for(
      '/',
      {
        'REMOTE_ADDR' => ip,
        'HTTP_USER_AGENT' => user_agent
      }.merge(extra_env)
    )

    Sinatra::Request.new(env)
  end

  def stub_ptr_lookup!(receiver, ptr: 'client.example.test')
    allow(receiver).to receive(:get_ptr).and_return(ptr)
  end

  def auth_user_agent
    @auth_user_agent ||= UserAgent.find_or_create!('RSpec auth agent')
  end

  def create_totp_device!(user:, label: 'Phone', confirmed: true, enabled: true,
                          secret: nil, recovery_code: nil)
    UserTotpDevice.create!(
      user:,
      label:,
      secret: secret || ROTP::Base32.random,
      confirmed:,
      enabled:,
      recovery_code: recovery_code && VpsAdmin::API::CryptoProviders::Bcrypt.encrypt(nil, recovery_code)
    )
  end

  def create_auth_token!(user:, purpose: 'mfa', valid_to: 5.minutes.from_now, opts: nil)
    Token.for_new_record!(valid_to) do |token|
      AuthToken.create!(
        user:,
        token:,
        purpose:,
        opts:,
        api_ip_addr: '127.0.0.1',
        api_ip_ptr: 'localhost',
        client_ip_addr: '127.0.0.1',
        client_ip_ptr: 'localhost',
        user_agent: auth_user_agent,
        client_version: 'RSpec auth'
      )
    end
  end

  def create_webauthn_challenge!(user:, type:, valid_to: 5.minutes.from_now)
    Token.for_new_record!(valid_to) do |token|
      WebauthnChallenge.create!(
        user:,
        token:,
        challenge_type: type,
        challenge: SecureRandom.hex(32),
        api_ip_addr: '127.0.0.1',
        api_ip_ptr: 'localhost',
        client_ip_addr: '127.0.0.1',
        client_ip_ptr: 'localhost',
        user_agent: auth_user_agent,
        client_version: 'RSpec auth'
      )
    end
  end

  def create_oauth2_client!(attrs = {})
    defaults = {
      name: "RSpec OAuth #{SecureRandom.hex(4)}",
      client_id: "rspec-client-#{SecureRandom.hex(6)}",
      redirect_uri: 'https://example.test/callback'
    }

    client = Oauth2Client.new(defaults.merge(attrs.except(:client_secret)))
    client.set_secret(attrs.fetch(:client_secret, 'secret'))
    client.save!
    client
  end

  def create_user_device!(user:, known: false, valid_to: 3.months.from_now,
                          skip_multi_factor_auth_until: nil,
                          last_next_multi_factor_auth: '')
    Token.for_new_record!(valid_to) do |token|
      UserDevice.create!(
        user:,
        token:,
        client_ip_addr: '127.0.0.1',
        client_ip_ptr: 'localhost',
        user_agent: auth_user_agent,
        known:,
        skip_multi_factor_auth_until:,
        last_next_multi_factor_auth:,
        last_seen_at: Time.now
      )
    end
  end

  def create_single_sign_on!(user:, valid_to: 5.minutes.from_now)
    Token.for_new_record!(valid_to) do |token|
      SingleSignOn.create!(
        user:,
        token:
      )
    end
  end

  def create_oauth2_authorization!(user:, client:, scope: ['all'], code_valid_to: 5.minutes.from_now,
                                   user_session: nil, sso: nil, refresh_valid_to: nil,
                                   user_device: nil)
    code = Token.get!(valid_to: code_valid_to)
    refresh_token = refresh_valid_to && Token.get!(valid_to: refresh_valid_to)

    Oauth2Authorization.create!(
      oauth2_client: client,
      user:,
      code:,
      scope:,
      user_session:,
      refresh_token:,
      single_sign_on: sso,
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      user_agent: auth_user_agent,
      user_device: user_device || create_user_device!(user:)
    )
  end

  def create_open_session!(user:, auth_type:, token_lifetime: 'fixed', token_interval: 3600,
                           label: 'RSpec session', scope: ['all'], valid_to: nil, admin: nil)
    if auth_type.to_s != 'basic'
      valid_to =
        if token_lifetime.to_s == 'permanent'
          nil
        else
          valid_to || (Time.now + token_interval)
        end
    end

    attrs = {
      user:,
      admin:,
      auth_type:,
      scope:,
      api_ip_addr: '127.0.0.1',
      api_ip_ptr: 'localhost',
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      user_agent: auth_user_agent,
      client_version: 'RSpec auth',
      token_lifetime:,
      token_interval:,
      label:
    }

    if auth_type.to_s == 'basic'
      UserSession.create!(attrs)
    else
      Token.for_new_record!(valid_to) do |token|
        UserSession.create!(attrs.merge(token:, token_str: token.token))
      end
    end
  end
end

RSpec.configure do |config|
  config.include AuthOperationHelpers

  config.before do
    User.current = nil
    UserSession.current = nil
  end
end
