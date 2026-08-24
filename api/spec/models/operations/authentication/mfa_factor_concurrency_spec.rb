# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe VpsAdmin::API::Operations::Authentication::MfaFactorChange,
               :no_transaction do
  # Committed fixtures shared with independent database connections have to be
  # created outside the per-example transaction and passed through the context.
  # rubocop:disable RSpec/InstanceVariable
  def build_factor_state(type:, recovery:)
    user = create_lifecycle_user!
    user.update!(
      enable_multi_factor_auth: true,
      enable_oauth2_auth: true
    )

    factor =
      if type == :totp
        create_totp_device!(user:)
      else
        WebauthnCredential.create!(
          user:,
          label: 'Concurrency passkey',
          external_id: Base64.strict_encode64("raw-#{SecureRandom.hex(8)}"),
          public_key: 'spec-public-key',
          sign_count: 0
        )
      end

    authority =
      if recovery
        request = PasswordRecoveryRequest.create!(
          recipient_email: user.email,
          locale: 'en'
        )
        password_recovery = request.password_recoveries.create!(
          user:,
          outcome: :recoverable,
          email_snapshot: user.email,
          email_token_digest: PasswordRecovery.digest_token(SecureRandom.hex(16)),
          email_expires_at: 1.hour.from_now,
          email_consumed_at: Time.current,
          session_token_digest: PasswordRecovery.digest_token(SecureRandom.hex(16)),
          session_expires_at: 15.minutes.from_now
        )
        challenge = nil
        if type == :webauthn
          challenge = create_webauthn_challenge!(user:, type: :authentication)
          challenge.update!(password_recovery: password_recovery)
        end
        { request:, recovery: password_recovery, challenge: }
      else
        auth_token = create_auth_token!(user:, purpose: 'mfa')
        challenge = if type == :webauthn
                      create_webauthn_challenge!(user:, type: :authentication)
                    end
        { auth_token:, challenge: }
      end

    { type:, user:, factor:, recovery:, **authority }
  end

  before(:context) do
    @state = {}
    %i[
      recovery_totp_verify_first
      ordinary_totp_verify_first
      recovery_totp_revoke_first
      ordinary_totp_revoke_first
    ].each do |name|
      @state[name] = build_factor_state(
        type: :totp,
        recovery: name.to_s.start_with?('recovery')
      )
    end

    %i[
      recovery_webauthn_verify_first
      ordinary_webauthn_verify_first
      recovery_webauthn_revoke_first
      ordinary_webauthn_revoke_first
    ].each do |name|
      @state[name] = build_factor_state(
        type: :webauthn,
        recovery: name.to_s.start_with?('recovery')
      )
    end
  end

  after(:context) do
    @state.each_value do |item|
      item[:request]&.destroy!
      item[:challenge]&.destroy! if item[:challenge] && WebauthnChallenge.exists?(item[:challenge].id)
      item[:auth_token]&.destroy! if item[:auth_token] && AuthToken.exists?(item[:auth_token].id)
      item[:factor]&.destroy! if item[:factor] && item[:factor].class.exists?(item[:factor].id)
      item[:user]&.delete
    end
  end

  def run_race(started, continue, verification:, revocation:)
    results = Queue.new
    errors = Queue.new
    revoker_connection = Queue.new
    verifier = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << verification.call
      end
    rescue StandardError => e
      errors << e
    end

    Timeout.timeout(5) { started.pop }
    revoker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        revoker_connection << ActiveRecord::Base.connection.select_value(
          'SELECT CONNECTION_ID()'
        )
        revocation.call
      end
    rescue StandardError => e
      errors << e
    end

    connection_id = Timeout.timeout(5) { revoker_connection.pop }
    wait_for_blocking_query(connection_id, 'FOR UPDATE')
    blocked = revoker.alive?
    continue << true
    verifier.join(10)
    revoker.join(10)
    raise errors.pop unless errors.empty?

    [results.pop, blocked]
  end

  def wait_for_blocking_query(connection_id, fragment)
    Timeout.timeout(5) do
      loop do
        info = ActiveRecord::Base.connection.select_value(
          ApplicationRecord.sanitize_sql_array(
            ['SELECT INFO FROM information_schema.PROCESSLIST WHERE ID = ?', connection_id]
          )
        )
        break if info&.include?(fragment)

        sleep(0.01)
      end
    end
  end

  def parsed_webauthn_credential(factor, started: nil, continue: nil)
    raw_id = Base64.strict_decode64(factor.external_id)
    instance_double(
      WebAuthn::PublicKeyCredentialWithAssertion,
      raw_id:,
      sign_count: factor.sign_count + 1
    ).tap do |credential|
      allow(credential).to receive(:verify) do
        started << true if started
        continue&.pop
        true
      end
    end
  end

  it 'invalidates a recovery when its TOTP factor is disabled after verification' do
    item = @state.fetch(:recovery_totp_verify_first)
    started = Queue.new
    continue = Queue.new
    code = item[:factor].totp.now
    allow(ROTP::TOTP).to receive(:new).and_wrap_original do |method, *args, **kwargs|
      method.call(*args, **kwargs).tap do |totp|
        allow(totp).to receive(:verify).and_wrap_original do |verify, *verify_args, **verify_kwargs|
          started << true
          continue.pop
          verify.call(*verify_args, **verify_kwargs)
        end
      end
    end

    result, blocked = run_race(
      started,
      continue,
      verification: lambda {
        recovery = PasswordRecovery.find(item[:recovery].id)
        described_class = VpsAdmin::API::Operations::Authentication::PasswordRecoveryTotp
        described_class.run(recovery, code, build_request)
      },
      revocation: lambda {
        device = UserTotpDevice.find(item[:factor].id)
        VpsAdmin::API::Operations::TotpDevice::Disable.run(device)
      }
    )

    expect(blocked).to be(true)
    expect(result).to be_authenticated
    expect(item[:recovery].reload.invalidated_at).to be_present
  end

  it 'linearizes ordinary TOTP verification before a concurrent disable' do
    item = @state.fetch(:ordinary_totp_verify_first)
    started = Queue.new
    continue = Queue.new
    code = item[:factor].totp.now
    allow(ROTP::TOTP).to receive(:new).and_wrap_original do |method, *args, **kwargs|
      method.call(*args, **kwargs).tap do |totp|
        allow(totp).to receive(:verify).and_wrap_original do |verify, *verify_args, **verify_kwargs|
          started << true
          continue.pop
          verify.call(*verify_args, **verify_kwargs)
        end
      end
    end

    result, blocked = run_race(
      started,
      continue,
      verification: lambda {
        VpsAdmin::API::Operations::Authentication::Totp.run(
          item[:auth_token].token.to_s,
          code
        )
      },
      revocation: lambda {
        device = UserTotpDevice.find(item[:factor].id)
        VpsAdmin::API::Operations::TotpDevice::Disable.run(device)
      }
    )

    expect(blocked).to be(true)
    expect(result).to be_authenticated
    expect(item[:factor].reload.enabled).to be(false)
  end

  it 'rejects recovery and ordinary TOTP after their factors are disabled' do
    recovery_item = @state.fetch(:recovery_totp_revoke_first)
    ordinary_item = @state.fetch(:ordinary_totp_revoke_first)
    [recovery_item, ordinary_item].each do |item|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          device = UserTotpDevice.find(item[:factor].id)
          VpsAdmin::API::Operations::TotpDevice::Disable.run(device)
        end
      end.join
    end

    recovery_result = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        VpsAdmin::API::Operations::Authentication::PasswordRecoveryTotp.run(
          PasswordRecovery.find(recovery_item[:recovery].id),
          recovery_item[:factor].totp.now,
          build_request
        )
      end
    end.value
    ordinary_result = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        VpsAdmin::API::Operations::Authentication::Totp.run(
          ordinary_item[:auth_token].token.to_s,
          ordinary_item[:factor].totp.now
        )
      end
    end.value

    expect(ordinary_result).not_to be_authenticated
    expect(recovery_result).not_to be_authenticated
    expect(recovery_item[:recovery].reload.mfa_verified_at).to be_nil
  end

  it 'does not reverse recovery lock order against OAuth client deletion' do
    user = create_lifecycle_user!
    user.update!(enable_multi_factor_auth: true, enable_oauth2_auth: true)
    device = create_totp_device!(user:)
    client = create_oauth2_client!
    request = PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en',
      oauth2_client: client
    )
    recoveries = 2.times.map do
      request.password_recoveries.create!(
        user:,
        outcome: :recoverable,
        email_snapshot: user.email,
        email_token_digest: nil,
        email_expires_at: 1.hour.from_now,
        email_consumed_at: Time.current,
        session_token_digest: PasswordRecovery.digest_token(SecureRandom.hex(16)),
        session_expires_at: 15.minutes.from_now
      )
    end
    recoveries.first.verify_mfa_with!(device)

    before_recovery_locks = Queue.new
    continue_verification = Queue.new
    allow(PasswordRecovery).to receive(:lock_for_totp_verification)
      .and_wrap_original do |method, *args, **kwargs|
        before_recovery_locks << true
        continue_verification.pop
        method.call(*args, **kwargs)
      end

    verification_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class = VpsAdmin::API::Operations::Authentication::PasswordRecoveryTotp
        described_class.run(
          PasswordRecovery.find(recoveries.last.id),
          device.totp.now,
          build_request
        )
      end
    end
    Timeout.timeout(5) { before_recovery_locks.pop }

    deletion_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Oauth2Client.find(client.id).destroy_with_password_recoveries!
      end
    end
    Timeout.timeout(5) { deletion_thread.value }
    continue_verification << true
    result = Timeout.timeout(5) { verification_thread.value }

    expect(result).not_to be_authenticated
    expect(recoveries.map { |recovery| recovery.reload.invalidated_at }).to all(be_present)
  ensure
    continue_verification << true if verification_thread&.alive?
    verification_thread&.join(5)
    deletion_thread&.join(5)
    request&.destroy! if request && PasswordRecoveryRequest.exists?(request.id)
    device&.destroy! if device && UserTotpDevice.exists?(device.id)
    client&.destroy! if client && Oauth2Client.exists?(client.id)
    user&.delete if user && User.exists?(user.id)
  end

  it 'invalidates a recovery when its passkey is deleted after verification' do
    item = @state.fetch(:recovery_webauthn_verify_first)
    started = Queue.new
    continue = Queue.new
    parsed = parsed_webauthn_credential(item[:factor], started:, continue:)
    allow(WebAuthn::Credential).to receive(:from_get).and_return(parsed)

    result, blocked = run_race(
      started,
      continue,
      verification: lambda {
        VpsAdmin::API::Operations::Authentication::PasswordRecoveryWebauthn.run(
          PasswordRecovery.find(item[:recovery].id),
          WebauthnChallenge.find(item[:challenge].id),
          {},
          build_request
        )
      },
      revocation: lambda {
        credential = WebauthnCredential.find(item[:factor].id)
        VpsAdmin::API::Operations::WebauthnCredential::Delete.run(credential)
      }
    )

    expect(blocked).to be(true)
    expect(result).to be_authenticated
    expect(item[:recovery].reload.invalidated_at).to be_present
  end

  it 'linearizes ordinary passkey verification before a concurrent delete' do
    item = @state.fetch(:ordinary_webauthn_verify_first)
    started = Queue.new
    continue = Queue.new
    parsed = parsed_webauthn_credential(item[:factor], started:, continue:)
    allow(WebAuthn::Credential).to receive(:from_get).and_return(parsed)

    _result, blocked = run_race(
      started,
      continue,
      verification: lambda {
        VpsAdmin::API::Operations::Authentication::Webauthn.run(
          AuthToken.find(item[:auth_token].id),
          WebauthnChallenge.find(item[:challenge].id),
          {}
        )
      },
      revocation: lambda {
        credential = WebauthnCredential.find(item[:factor].id)
        VpsAdmin::API::Operations::WebauthnCredential::Delete.run(credential)
      }
    )

    expect(blocked).to be(true)
    expect(item[:auth_token].reload.fulfilled).to be(true)
    expect(WebauthnCredential.exists?(item[:factor].id)).to be(false)
  end

  it 'rejects recovery and ordinary passkey after their credentials are deleted' do
    recovery_item = @state.fetch(:recovery_webauthn_revoke_first)
    ordinary_item = @state.fetch(:ordinary_webauthn_revoke_first)
    [recovery_item, ordinary_item].each do |item|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          credential = WebauthnCredential.find(item[:factor].id)
          VpsAdmin::API::Operations::WebauthnCredential::Delete.run(credential)
        end
      end.join
    end

    recovery_parsed = parsed_webauthn_credential(recovery_item[:factor])
    allow(WebAuthn::Credential).to receive(:from_get).and_return(recovery_parsed)
    recovery_result = VpsAdmin::API::Operations::Authentication::PasswordRecoveryWebauthn.run(
      PasswordRecovery.find(recovery_item[:recovery].id),
      WebauthnChallenge.find(recovery_item[:challenge].id),
      {},
      build_request
    )
    ordinary_parsed = parsed_webauthn_credential(ordinary_item[:factor])
    allow(WebAuthn::Credential).to receive(:from_get).and_return(ordinary_parsed)
    expect do
      VpsAdmin::API::Operations::Authentication::Webauthn.run(
        AuthToken.find(ordinary_item[:auth_token].id),
        WebauthnChallenge.find(ordinary_item[:challenge].id),
        {}
      )
    end.to raise_error(ActiveRecord::RecordNotFound)

    expect(recovery_result).not_to be_authenticated
    expect(recovery_item[:recovery].reload.mfa_verified_at).to be_nil
  end
  # rubocop:enable RSpec/InstanceVariable
end
