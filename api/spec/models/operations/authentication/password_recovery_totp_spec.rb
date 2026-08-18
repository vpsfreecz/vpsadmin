# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::PasswordRecoveryTotp do
  let(:user) do
    create_lifecycle_user!.tap do |record|
      record.update!(enable_multi_factor_auth: true)
    end
  end
  let!(:device) do
    create_totp_device!(user:, recovery_code: 'recovery-code')
  end
  let(:request_record) do
    PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en'
    )
  end
  let(:recovery) do
    PasswordRecovery.create!(
      password_recovery_request: request_record,
      user:,
      outcome: :recoverable,
      email_snapshot: user.email,
      email_token_digest: PasswordRecovery.digest_token('spent'),
      email_expires_at: 1.hour.from_now,
      email_consumed_at: Time.current,
      session_token_digest: PasswordRecovery.digest_token('session'),
      session_expires_at: 15.minutes.from_now
    )
  end
  let(:request) { build_request }

  def code_at(time)
    allow(Time).to receive(:now).and_return(time)
    device.totp.at(time)
  end

  it 'verifies TOTP and marks the recovery MFA stage complete' do
    result = described_class.run(recovery, code_at(Time.at(1_700_000_000)), request)

    expect(result).to be_authenticated
    expect(recovery.reload.mfa_verified_at).to be_present
    expect(device.reload.use_count).to eq(1)
  end

  it 'accepts a recovery code and disables its TOTP device' do
    unlock_transaction_signer!
    ensure_available_node_status!(SpecSeed.node)
    VpsAdmin::API::MailTemplates.install_defaults!

    result = described_class.run(recovery, 'recovery-code', request)

    expect(result).to be_authenticated
    expect(result).to be_used_recovery_code
    expect(device.reload.enabled).to be(false)
    expect(recovery.reload.mfa_verified_at).to be_present
  end

  it 'invalidates the recovery after five bad codes' do
    result = nil

    PasswordRecovery::MAX_TOTP_FAILED_ATTEMPTS.times do
      result = described_class.run(recovery, '000000', request)
    end

    expect(result).to be_failure_limit_exceeded
    expect(recovery.reload.invalidated_at).to be_present
    expect(recovery.totp_failed_attempts).to eq(PasswordRecovery::MAX_TOTP_FAILED_ATTEMPTS)
  end

  it 'locks the user before recovery state when recording a bad code' do
    lock_queries = []

    ActiveSupport::Notifications.subscribed(
      lambda do |_name, _start, _finish, _id, payload|
        lock_queries << payload[:sql] if payload[:sql].include?('FOR UPDATE')
      end,
      'sql.active_record'
    ) do
      described_class.run(recovery, '000000', request)
    end

    expect(lock_queries.first(2).map { |sql| sql[/FROM `([^`]+)`/, 1] }).to eq(
      %w[users password_recoveries]
    )
  end

  it 'rejects replay of a TOTP code through another recovery' do
    second_recovery = recovery.dup
    second_recovery.email_token_digest = PasswordRecovery.digest_token('spent-two')
    second_recovery.session_token_digest = PasswordRecovery.digest_token('session-two')
    second_recovery.save!
    code = code_at(Time.at(1_700_000_000))

    first_result = described_class.run(recovery, code, request)
    second_result = described_class.run(second_recovery, code, request)

    expect(first_result).to be_authenticated
    expect(second_result).not_to be_authenticated
    expect(device.reload.use_count).to eq(1)
  end
end
