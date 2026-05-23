# frozen_string_literal: true

require 'webauthn/fake_client'

RSpec.describe 'VpsAdmin::API::Resources::Webauthn' do
  before do
    header 'Accept', 'application/json'
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:origin) { SysConfig.get(:core, :api_url) }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  def registration_begin_path
    vpath('/webauthn/registration/begin')
  end

  def registration_finish_path
    vpath('/webauthn/registration/finish')
  end

  def authentication_begin_path
    vpath('/webauthn/authentication/begin')
  end

  def authentication_finish_path
    vpath('/webauthn/authentication/finish')
  end

  def json_post(path, payload = {})
    body = payload.nil? ? '{}' : JSON.dump(payload)
    post path, body, { 'CONTENT_TYPE' => 'application/json' }
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def registration_response
    json.dig('response', 'registration') || {}
  end

  def authentication_response
    json.dig('response', 'authentication') || {}
  end

  def find_challenge(token_value)
    WebauthnChallenge.joins(:token).where(tokens: { token: token_value }).take
  end

  def create_auth_token(target_user)
    Token.for_new_record!(Time.now + 300) do |token|
      AuthToken.create!(user: target_user, token: token, purpose: :mfa)
    end
  end

  def suspend_user!(target_user = user)
    target_user.update!(
      object_state: :suspended,
      enable_basic_auth: true,
      enable_multi_factor_auth: false,
      lockout: false,
      password_reset: false
    )
    mark_user_paid_until!(target_user)
  end

  def begin_registration_for(target_user)
    as(target_user) { json_post registration_begin_path }
    expect_status(200)
    expect(json['status']).to be(true)
    registration_response
  end

  def finish_registration_for(target_user, challenge_token:, label:, credential:)
    as(target_user) do
      json_post registration_finish_path,
                registration: {
                  challenge_token: challenge_token,
                  label: label,
                  public_key_credential: credential
                }
    end
  end

  def register_credential_for(target_user, label: 'Spec Key', client: fake_client)
    response = begin_registration_for(target_user)
    options = response.fetch('options')

    credential = client.create(
      challenge: options.fetch('challenge'),
      rp_id: options.dig('rp', 'id')
    )

    finish_registration_for(target_user,
                            challenge_token: response.fetch('challenge_token'),
                            label: label,
                            credential: credential)

    expect_status(200)
    expect(json['status']).to be(true)

    target_user.reload
    target_user.webauthn_credentials.order(:id).last
  end

  describe 'Registration::Begin' do
    it 'rejects unauthenticated access' do
      json_post registration_begin_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns options and stores a challenge' do
      user.update!(webauthn_id: nil)
      response = begin_registration_for(user)

      expect(response['challenge_token']).to be_a(String)
      options = response['options']
      expect(options).to be_a(Hash)
      expect(options['challenge']).to be_a(String)
      expect(options['rp']).to be_a(Hash)
      expect(options['user']).to be_a(Hash)
      expect(options['pubKeyCredParams']).to be_a(Array)

      challenge = find_challenge(response['challenge_token'])
      expect(challenge).not_to be_nil
      expect(challenge.user_id).to eq(user.id)
      expect(challenge.registration?).to be(true)
      expect(user.reload.webauthn_id).not_to be_nil
    end

    it 'denies creating a registration challenge while suspended' do
      user.update!(webauthn_id: nil)
      suspend_user!

      expect do
        as(user) { json_post registration_begin_path }
      end.not_to change(WebauthnChallenge, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('Access forbidden')
      expect(user.reload.webauthn_id).to be_nil
    end

    it 'records challenge client address from forwarded headers' do
      header 'Client-IP', '203.0.113.80'
      header 'X-Real-IP', '203.0.113.81'

      response = begin_registration_for(user)
      challenge = find_challenge(response.fetch('challenge_token'))

      expect(challenge.client_ip_addr).to eq('203.0.113.80')
      expect(challenge.client_ip_addr).not_to eq(challenge.api_ip_addr)
      expect(challenge.client_ip_addr).not_to eq('203.0.113.81')
    end
  end

  describe 'Registration::Finish' do
    it 'rejects unauthenticated access' do
      json_post registration_finish_path, registration: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns validation errors for missing input' do
      as(user) { json_post registration_finish_path, registration: { label: 'Spec Key' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('challenge_token', 'public_key_credential')
    end

    it 'does not allow other users to finish the challenge' do
      response = begin_registration_for(user)

      finish_registration_for(other_user,
                              challenge_token: response['challenge_token'],
                              label: 'Spec Key',
                              credential: { 'id' => 'invalid' })

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'fails with invalid credential data' do
      response = begin_registration_for(user)
      options = response.fetch('options')
      invalid_credential = fake_client.create(
        challenge: WebAuthn.standard_encoder.encode('invalid-challenge'),
        rp_id: options.dig('rp', 'id')
      )

      finish_registration_for(user,
                              challenge_token: response['challenge_token'],
                              label: 'Spec Key',
                              credential: invalid_credential)

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'creates a credential with a fake client' do
      credential = register_credential_for(user, label: 'Spec Key', client: fake_client)

      expect(credential).not_to be_nil
      expect(credential.label).to eq('Spec Key')
      expect(credential.public_key).not_to be_nil
    end

    it 'denies finishing registration while suspended' do
      response = begin_registration_for(user)
      options = response.fetch('options')
      credential = fake_client.create(
        challenge: options.fetch('challenge'),
        rp_id: options.dig('rp', 'id')
      )
      suspend_user!

      expect do
        finish_registration_for(user,
                                challenge_token: response.fetch('challenge_token'),
                                label: 'Suspended Key',
                                credential: credential)
      end.not_to change(WebauthnCredential, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('Access forbidden')
      expect(find_challenge(response.fetch('challenge_token'))).not_to be_nil
    end
  end

  describe 'Authentication::Begin' do
    it 'returns validation errors for missing auth_token' do
      json_post authentication_begin_path, authentication: {}

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('auth_token')
    end

    it 'returns 404 for an invalid auth_token' do
      json_post authentication_begin_path, authentication: { auth_token: 'missing' }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'rejects an expired auth_token without creating a challenge' do
      auth_token = create_auth_token(user)
      auth_token.token.update!(valid_to: 1.minute.ago)

      expect do
        json_post authentication_begin_path, authentication: { auth_token: auth_token.token.to_s }
      end.not_to change(WebauthnChallenge, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('auth token expired')
    end

    it 'returns options and stores a challenge' do
      auth_token = create_auth_token(user)

      json_post authentication_begin_path, authentication: { auth_token: auth_token.token.to_s }

      expect_status(200)
      expect(json['status']).to be(true)
      response = authentication_response

      expect(response['challenge_token']).to be_a(String)
      options = response['options']
      expect(options).to be_a(Hash)
      expect(options['challenge']).to be_a(String)
      expect(options['allowCredentials']).to be_a(Array)

      challenge = find_challenge(response['challenge_token'])
      expect(challenge).not_to be_nil
      expect(challenge.user_id).to eq(user.id)
      expect(challenge.authentication?).to be(true)
    end
  end

  describe 'Authentication::Finish' do
    it 'returns validation errors for missing input' do
      json_post authentication_finish_path, authentication: { challenge_token: 'missing' }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('auth_token', 'public_key_credential')
    end

    it 'returns 404 when auth_token does not match the challenge user' do
      auth_token = create_auth_token(user)
      other_token = create_auth_token(other_user)

      json_post authentication_begin_path, authentication: { auth_token: auth_token.token.to_s }
      response = authentication_response

      json_post authentication_finish_path,
                authentication: {
                  challenge_token: response['challenge_token'],
                  auth_token: other_token.token.to_s,
                  public_key_credential: { 'id' => 'invalid' }
                }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'fails with invalid credential data' do
      register_credential_for(user, label: 'Spec Key', client: fake_client)
      auth_token = create_auth_token(user)

      json_post authentication_begin_path, authentication: { auth_token: auth_token.token.to_s }
      response = authentication_response
      options = response.fetch('options')
      allow_ids = Array(options['allowCredentials']).map { |cred| cred['id'] }
      invalid_assertion = fake_client.get(
        challenge: WebAuthn.standard_encoder.encode('invalid-challenge'),
        allow_credentials: allow_ids,
        rp_id: options['rpId']
      )

      json_post authentication_finish_path,
                authentication: {
                  challenge_token: response['challenge_token'],
                  auth_token: auth_token.token.to_s,
                  public_key_credential: invalid_assertion
                }

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'authenticates using a fake client' do
      credential = register_credential_for(user, label: 'Spec Key', client: fake_client)
      auth_token = create_auth_token(user)

      json_post authentication_begin_path, authentication: { auth_token: auth_token.token.to_s }
      response = authentication_response
      challenge = find_challenge(response['challenge_token'])

      options = response.fetch('options')
      allow_ids = Array(options['allowCredentials']).map { |cred| cred['id'] }

      assertion = fake_client.get(
        challenge: options.fetch('challenge'),
        allow_credentials: allow_ids,
        rp_id: options['rpId']
      )

      json_post authentication_finish_path,
                authentication: {
                  challenge_token: response['challenge_token'],
                  auth_token: auth_token.token.to_s,
                  public_key_credential: assertion
                }

      expect_status(200)
      expect(json['status']).to be(true)

      credential.reload
      expect(credential.last_use_at).not_to be_nil
      expect(credential.use_count).to eq(1)

      auth_token.reload
      expect(auth_token.fulfilled).to be(true)
      expect(WebauthnChallenge.exists?(challenge.id)).to be(false)
    end
  end
end
