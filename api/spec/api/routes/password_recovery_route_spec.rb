# frozen_string_literal: true

require 'json'
require 'webauthn/fake_client'

RSpec.describe VpsAdmin::API::Authentication::PasswordRecovery do
  before do
    unlock_transaction_signer!
    VpsAdmin::API::MailTemplates.install_defaults!
    ensure_available_node_status!(SpecSeed.node)
    SysConfig.find_or_create_by!(category: 'core', name: 'password_recovery_enabled').update!(value: true)
    SysConfig.find_or_create_by!(category: 'core', name: 'auth_url').update!(value: 'http://example.org')
    SysConfig.find_or_create_by!(category: 'core', name: 'logo_url').update!(
      value: 'https://assets.example.test/vpsfree-logo.png'
    )
    SysConfig.find_or_create_by!(category: 'core', name: 'support_mail').update!(value: 'support@example.test')
  end

  def csrf_from_body
    last_response.body.match(/name="csrf_token" value="([^"]+)"/)&.[](1)
  end

  def password_changed_mails
    MailLog.joins(:mail_template).where(
      mail_templates: { name: 'user_password_changed' }
    )
  end

  def create_user_with_totp
    create_lifecycle_user!.tap do |user|
      user.update!(enable_multi_factor_auth: true)
      create_totp_device!(user:)
    end
  end

  def create_recovery(user:, client: nil, email_lifetime: 1.hour)
    raw_token = PasswordRecovery.generate_token
    recovery_request = PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en',
      oauth2_client: client
    )
    recovery = recovery_request.password_recoveries.create!(
      user:,
      outcome: :recoverable,
      email_snapshot: user.email,
      email_token_digest: PasswordRecovery.digest_token(raw_token),
      email_expires_at: Time.current + email_lifetime
    )
    [recovery, raw_token]
  end

  def exchange_email_token(raw_token)
    get '/oauth2/password-reset/continue'
    expect(last_response.status).to eq(200)
    csrf = csrf_from_body

    post '/oauth2/password-reset/continue', csrf_token: csrf, token: raw_token
    expect(last_response.status).to eq(303)
    expect(last_response.headers['Location']).to end_with('/oauth2/password-reset/verify')
    csrf
  end

  def register_webauthn_credential(user)
    as(user, password: 'secret123') do
      post vpath('/webauthn/registration/begin'), '{}', 'CONTENT_TYPE' => 'application/json'
    end
    response = json.fetch('response').fetch('registration')
    options = response.fetch('options')
    fake_client = WebAuthn::FakeClient.new(SysConfig.get(:core, :api_url))
    credential = fake_client.create(
      challenge: options.fetch('challenge'),
      rp_id: options.dig('rp', 'id')
    )

    as(user, password: 'secret123') do
      post vpath('/webauthn/registration/finish'), JSON.dump(
        registration: {
          challenge_token: response.fetch('challenge_token'),
          label: 'Recovery passkey',
          public_key_credential: credential
        }
      ), 'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(true)

    [fake_client, user.webauthn_credentials.order(:id).last]
  end

  it 'is unavailable while the feature flag is disabled' do
    SysConfig.find_by!(category: 'core', name: 'password_recovery_enabled').update!(value: false)

    get '/oauth2/password-reset'

    expect(last_response.status).to eq(404)
  end

  it 'shows the MFA requirement without disclosing account state' do
    get '/oauth2/password-reset'

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('available only for accounts with TOTP or a passkey configured')
    expect(last_response.body).not_to include('We will not disclose')
    expect(last_response.body).not_to include('email will explain how to contact support')
    expect(last_response.body).to include(
      '<img class="logo" src="https://assets.example.test/vpsfree-logo.png" alt="vpsFree.cz">'
    )
    expect(last_response.headers['Cache-Control']).to include('no-store')
    expect(last_response.headers['Referrer-Policy']).to eq('no-referrer')
    expect(last_response.headers['X-Frame-Options']).to eq('DENY')
    expect(last_response.headers['Content-Security-Policy']).to include("frame-ancestors 'none'")
    expect(last_response.headers['Content-Security-Policy']).to include(
      "img-src 'self' https://assets.example.test"
    )
  end

  it 'omits a logo that cannot be loaded safely' do
    SysConfig.find_by!(category: 'core', name: 'logo_url').update!(
      value: 'javascript:alert(1)'
    )

    get '/oauth2/password-reset'

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('class="logo"')
    expect(last_response.headers['Content-Security-Policy']).to include("img-src 'self'")
    expect(last_response.headers['Content-Security-Policy']).not_to include('javascript:')
  end

  it 'returns the same confirmation after every submitted identifier' do
    known_user = create_user_with_totp
    allow(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .to receive(:run)

    get '/oauth2/password-reset'
    csrf = csrf_from_body
    expect do
      post '/oauth2/password-reset', csrf_token: csrf, identifier: known_user.email
    end.to change(PasswordRecoverySubmission, :count).by(1)
    follow_redirect!
    known_body = last_response.body

    get '/oauth2/password-reset'
    csrf = csrf_from_body
    expect do
      post '/oauth2/password-reset', csrf_token: csrf, identifier: 'unknown@example.test'
    end.to change(PasswordRecoverySubmission, :count).by(1)
    follow_redirect!

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq(known_body)
    expect(last_response.body).to include(
      'If a matching account was found, instructions were sent to its primary address'
    )
    expect(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .not_to have_received(:run)
  end

  it 'returns an explicit rate-limit error for a repeated submitted value' do
    get '/oauth2/password-reset'
    post '/oauth2/password-reset',
         csrf_token: csrf_from_body,
         identifier: 'Member@Example.Test'
    expect(last_response.status).to eq(303)

    get '/oauth2/password-reset'
    expect do
      post '/oauth2/password-reset',
           csrf_token: csrf_from_body,
           identifier: 'member@example.test'
    end.not_to change(PasswordRecoverySubmission, :count)

    expect(last_response.status).to eq(429)
    expect(last_response.headers['Retry-After'].to_i).to be_between(1, 600)
    expect(last_response.body).to include(
      'Too many password recovery requests. Wait a few minutes and try again.'
    )
    expect(last_response.body).to include('value="member@example.test"')
  end

  it 'returns an explicit temporary error when the unfinished queue is full' do
    stub_const('PasswordRecoverySubmission::MAX_PENDING', 0)

    get '/oauth2/password-reset'
    post '/oauth2/password-reset',
         csrf_token: csrf_from_body,
         identifier: 'member@example.test'

    expect(last_response.status).to eq(503)
    expect(last_response.body).to include(
      'Password recovery is temporarily unavailable. Try again later.'
    )
  end

  it 'rejects a reused or expired email token' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)

    get '/oauth2/password-reset/continue'
    csrf = csrf_from_body
    post '/oauth2/password-reset/continue', csrf_token: csrf, token: raw_token

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include('invalid, expired, or has already been used')
    expect(recovery.reload.email_consumed_at).to be_present

    _expired_recovery, expired_token = create_recovery(
      user:,
      email_lifetime: -1.minute
    )
    get '/oauth2/password-reset/continue'
    post '/oauth2/password-reset/continue',
         csrf_token: csrf_from_body,
         token: expired_token

    expect(last_response.status).to eq(400)
    expect(last_response.body).to include('invalid, expired, or has already been used')
  end

  it 'rejects an email token completed after its active lookup' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    allow(PasswordRecovery).to receive(:find_by_email_token).and_wrap_original do |original, token|
      found = original.call(token)
      PasswordRecovery.where(id: found.id).update_all(completed_at: Time.current)
      found
    end

    get '/oauth2/password-reset/continue'
    post '/oauth2/password-reset/continue',
         csrf_token: csrf_from_body,
         token: raw_token

    expect(last_response.status).to eq(400)
    expect(recovery.reload.email_consumed_at).to be_nil
  end

  it 'invalidates an expired recovery session' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    recovery.update!(session_expires_at: 1.minute.ago)

    get '/oauth2/password-reset/verify'

    expect(last_response.status).to eq(400)
    expect(recovery.reload.invalidated_at).to be_present
  end

  it 'keeps password errors in the password stage and completes the reset after TOTP' do
    header 'User-Agent', 'Recovery route spec'
    user = create_user_with_totp
    client = create_oauth2_client!(
      authorization_start_uri: 'https://service.example.test/sign-in?from=recovery'
    )
    recovery, raw_token = create_recovery(user:, client:)
    old_session = create_open_session!(user:, auth_type: 'token')
    initial_session_count = user.user_sessions.count
    exchange_email_token(raw_token)

    get '/oauth2/password-reset/verify'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Verify your identity')
    csrf = csrf_from_body
    post '/oauth2/password-reset/verify/totp',
         csrf_token: csrf,
         totp_code: user.user_totp_devices.first.totp.now
    expect(last_response.status).to eq(303)

    get '/oauth2/password-reset/password'
    expect(last_response.status).to eq(200)
    csrf = csrf_from_body
    post '/oauth2/password-reset/password',
         csrf_token: csrf,
         new_password: 'new-secret-password',
         repeat_new_password: 'different-password',
         sign_out_all: '1'
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include('The passwords do not match')
    expect(recovery.reload.mfa_verified_at).to be_present
    expect(password_changed_mails).to be_empty

    csrf = csrf_from_body
    expect do
      post '/oauth2/password-reset/password',
           csrf_token: csrf,
           new_password: 'new-secret-password',
           repeat_new_password: 'new-secret-password',
           sign_out_all: '1'
    end.to change(password_changed_mails, :count).by(1)

    expect(last_response.status).to eq(303)
    expect(last_response.headers['Location']).to eq(
      'https://service.example.test/sign-in?from=recovery'
    )
    expect(recovery.reload.completed_at).to be_present
    expect(old_session.reload.closed_at).to be_present
    expect(user.user_sessions.count).to eq(initial_session_count)
    expect(
      VpsAdmin::API::Operations::Authentication::Password.run(
        user.login,
        'new-secret-password',
        multi_factor: false
      )
    ).to be_authenticated
    expect(
      VpsAdmin::API::Operations::Authentication::Password.run(
        user.login,
        'secret123',
        multi_factor: false
      )
    ).not_to be_authenticated
    notification = password_changed_mails.order(:id).last
    expect(notification.user).to eq(user)
    expect(notification.text_plain).to include('Recovery route spec')
  end

  it 'preserves existing sessions when the checkbox is not submitted' do
    user = create_user_with_totp
    client = create_oauth2_client!
    sso = create_single_sign_on!(user:)
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      sso:
    )
    code_id = authorization.code.id
    recovery, raw_token = create_recovery(user:)
    old_session = create_open_session!(user:, auth_type: 'token')
    mfa_token = create_auth_token!(user:, purpose: 'mfa')
    password_token = create_auth_token!(user:, purpose: 'reset_password')
    token_ids = [mfa_token.token_id, password_token.token_id]
    exchange_email_token(raw_token)
    recovery.update!(mfa_verified_at: Time.current)

    get '/oauth2/password-reset/password'
    post '/oauth2/password-reset/password',
         csrf_token: csrf_from_body,
         new_password: 'new-secret-password',
         repeat_new_password: 'new-secret-password'

    expect(last_response.status).to eq(303)
    expect(old_session.reload.closed_at).to be_nil
    expect(AuthToken.where(id: [mfa_token.id, password_token.id])).to be_empty
    expect(Token.where(id: token_ids)).to be_empty
    expect(authorization.reload.code.id).to eq(code_id)
    expect(authorization).to be_active
    expect(sso.reload.token).to be_present

    expect(last_response.headers['Location']).to end_with('/oauth2/password-reset/complete')
    follow_redirect!
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Your password has been changed')
  end

  it 'locks the user before recovery state when changing the password' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    recovery.update!(mfa_verified_at: Time.current)
    lock_queries = []

    get '/oauth2/password-reset/password'
    ActiveSupport::Notifications.subscribed(
      lambda do |_name, _start, _finish, _id, payload|
        lock_queries << payload[:sql] if payload[:sql].include?('FOR UPDATE')
      end,
      'sql.active_record'
    ) do
      post '/oauth2/password-reset/password',
           csrf_token: csrf_from_body,
           new_password: 'new-secret-password',
           repeat_new_password: 'new-secret-password'
    end

    expect(last_response.status).to eq(303)
    expect(lock_queries.first(2).map { |sql| sql[/FROM `([^`]+)`/, 1] }).to eq(
      %w[users password_recoveries]
    )
  end

  it 'revokes pending OAuth and SSO state when signing out all sessions' do
    user = create_user_with_totp
    client = create_oauth2_client!
    sso = create_single_sign_on!(user:)
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      sso:
    )
    code_id = authorization.code.id
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    recovery.update!(mfa_verified_at: Time.current)

    get '/oauth2/password-reset/password'
    post '/oauth2/password-reset/password',
         csrf_token: csrf_from_body,
         new_password: 'new-secret-password',
         repeat_new_password: 'new-secret-password',
         sign_out_all: '1'

    expect(last_response.status).to eq(303)
    expect(authorization.reload.code).to be_nil
    expect(Token.exists?(code_id)).to be(false)
    expect(authorization).not_to be_active
    expect(sso.reload.token).to be_nil
  end

  it 'continues after a TOTP recovery code disables the last MFA device' do
    user = create_user_with_totp
    device = user.user_totp_devices.first
    device.update!(
      recovery_code: VpsAdmin::API::CryptoProviders::Bcrypt.encrypt(nil, 'recovery-code')
    )
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    allow(TransactionChains::User::TotpRecoveryCodeUsed).to receive(:fire)

    get '/oauth2/password-reset/verify'
    expect(last_response.body).to include('TOTP code')
    expect(last_response.body).not_to include('recovery code')
    post '/oauth2/password-reset/verify/totp',
         csrf_token: csrf_from_body,
         totp_code: 'incorrect-code'
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include('The TOTP code is not valid.')
    expect(last_response.body).not_to include('recovery code')

    post '/oauth2/password-reset/verify/totp',
         csrf_token: csrf_from_body,
         totp_code: 'recovery-code'

    get '/oauth2/password-reset/password'

    expect(last_response.status).to eq(200)
    expect(recovery.reload.mfa_verified_at).to be_present
    expect(device.reload.enabled).to be(false)
  end

  it 'keeps a valid flow at the MFA stage after a failed passkey attempt' do
    user = create_user_with_totp
    user.webauthn_credentials.create!(
      label: 'Spec passkey',
      external_id: Base64.strict_encode64('credential-id'),
      public_key: 'not-a-real-public-key',
      sign_count: 0
    )
    recovery, raw_token = create_recovery(user:)
    csrf = exchange_email_token(raw_token)

    header 'X-CSRF-Token', csrf
    header 'Content-Type', 'application/json'
    post '/oauth2/password-reset/verify/webauthn/begin', '{}'
    expect(last_response.status).to eq(200)
    challenge_token = JSON.parse(last_response.body).fetch('challenge_token')

    post '/oauth2/password-reset/verify/webauthn/finish', JSON.dump(
      challenge_token:,
      public_key_credential: {}
    )

    expect(last_response.status).to eq(422)
    expect(recovery.reload.mfa_verified_at).to be_nil
    get '/oauth2/password-reset/verify'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Verify your identity')
  end

  it 'rejects non-object passkey responses without failing the request' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    csrf = exchange_email_token(raw_token)

    header 'X-CSRF-Token', csrf
    header 'Content-Type', 'application/json'

    ['[]', 'null', '"invalid"'].each do |body|
      post '/oauth2/password-reset/verify/webauthn/finish', body

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)['status']).to be(false)
    end
    expect(recovery.reload.mfa_verified_at).to be_nil
  end

  it 'reloads and locks the user before committing a new password' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    recovery.update!(mfa_verified_at: Time.current)
    recovery.user
    User.where(id: user.id).update_all(email: 'changed@example.test')
    allow(PasswordRecovery).to receive(:find_by_session_token).and_return(recovery)

    get '/oauth2/password-reset/password'
    post '/oauth2/password-reset/password',
         csrf_token: csrf_from_body,
         new_password: 'new-secret-password',
         repeat_new_password: 'new-secret-password'

    expect(last_response.status).to eq(400)
    expect(recovery.reload.completed_at).to be_nil
    expect(
      VpsAdmin::API::Operations::Authentication::Password.run(
        user.login,
        'secret123',
        multi_factor: false
      )
    ).to be_authenticated
  end

  it 'rejects a recovery invalidated after its active lookup' do
    user = create_user_with_totp
    recovery, raw_token = create_recovery(user:)
    exchange_email_token(raw_token)
    recovery.update!(mfa_verified_at: Time.current)

    get '/oauth2/password-reset/password'
    csrf = csrf_from_body
    allow(PasswordRecovery).to receive(:find_by_session_token).and_wrap_original do |original, token|
      found = original.call(token)
      PasswordRecovery.where(id: found.id).update_all(invalidated_at: Time.current)
      found
    end

    post '/oauth2/password-reset/password',
         csrf_token: csrf,
         new_password: 'new-secret-password',
         repeat_new_password: 'new-secret-password'

    expect(last_response.status).to eq(400)
    expect(recovery.reload.completed_at).to be_nil
    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(
        user.reload.password,
        user.login,
        'secret123'
      )
    ).to be(true)
  end

  it 'verifies a recovery flow using a passkey' do
    user = create_lifecycle_user!
    user.update!(enable_multi_factor_auth: true)
    fake_client, credential = register_webauthn_credential(user)
    recovery, raw_token = create_recovery(user:)
    csrf = exchange_email_token(raw_token)

    header 'X-CSRF-Token', csrf
    header 'Content-Type', 'application/json'
    post '/oauth2/password-reset/verify/webauthn/begin', '{}'
    expect(last_response.status).to eq(200)
    begin_response = JSON.parse(last_response.body)
    options = begin_response.fetch('options')
    assertion = fake_client.get(
      challenge: options.fetch('challenge'),
      allow_credentials: options.fetch('allowCredentials').map { |item| item.fetch('id') },
      rp_id: options['rpId']
    )

    post '/oauth2/password-reset/verify/webauthn/finish', JSON.dump(
      challenge_token: begin_response.fetch('challenge_token'),
      public_key_credential: assertion
    )

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)['status']).to be(true)
    expect(recovery.reload.mfa_verified_at).to be_present
    expect(credential.reload.use_count).to eq(1)
    get '/oauth2/password-reset/password'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Choose a new password')
  end
end
