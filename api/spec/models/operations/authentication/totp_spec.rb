# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::Totp do
  let(:user) { SpecSeed.user }
  let!(:device) do
    create_totp_device!(
      user:,
      recovery_code: 'recovery-code'
    )
  end

  def code_at(time)
    allow(Time).to receive(:now).and_return(time)
    device.totp.at(time)
  end

  it 'raises AuthenticationError for an invalid auth token' do
    expect do
      described_class.run('missing', '000000')
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')
  end

  it 'raises AuthenticationError for an expired auth token' do
    auth_token = create_auth_token!(user:, purpose: 'mfa', valid_to: 1.minute.ago)

    expect do
      described_class.run(auth_token.token.to_s, '000000')
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')
  end

  it 'authenticates a valid TOTP code and destroys the MFA token' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    code = code_at(Time.at(1_700_000_000))

    result = described_class.run(auth_token.token.to_s, code)

    expect(result).to be_authenticated
    expect(result).not_to be_reset_password
    expect(result.used_recovery_code?).to be(false)
    expect(AuthToken.exists?(auth_token.id)).to be(false)

    device.reload
    expect(device.last_verification_at).to be_present
    expect(device.last_use_at).to eq(Time.at(1_700_000_000))
    expect(device.use_count).to eq(1)
  end

  it 'rewrites the auth token purpose when password reset is pending' do
    user.update!(password_reset: true)
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    code = code_at(Time.at(1_700_000_000))

    result = described_class.run(auth_token.token.to_s, code)

    expect(result).to be_authenticated
    expect(result).to be_reset_password
    expect(auth_token.reload).to be_reset_password
  end

  it 'authenticates a recovery code, disables the device, and reports it' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    recovery_request = PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en'
    )
    recovery = recovery_request.password_recoveries.create!(
      user:,
      outcome: :recoverable,
      email_snapshot: user.email,
      email_token_digest: PasswordRecovery.digest_token('ordinary-fallback'),
      email_expires_at: 1.hour.from_now
    )
    recovery.verify_mfa_with!(device)

    result = described_class.run(auth_token.token.to_s, 'recovery-code')

    expect(result).to be_authenticated
    expect(result.used_recovery_code?).to be(true)
    expect(result.recovery_device).to eq(device)
    expect(device.reload.enabled).to be(false)
    expect(recovery.reload.invalidated_at).to be_present
  end

  it 'does not consume a factor invalidated after token lookup' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    op = described_class.new
    lookups = 0
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

    expect do
      op.run(auth_token.token.to_s, 'recovery-code')
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')

    expect(device.reload.enabled).to be(true)
  end

  it 'leaves the token intact for an invalid code' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')

    result = described_class.run(auth_token.token.to_s, '000000')

    expect(result).not_to be_authenticated
    expect(result).not_to be_failure_limit_exceeded
    expect(result.auth_token).to eq(auth_token)
    expect(auth_token.reload.opts['totp_failed_attempts']).to eq(1)
    expect(AuthToken.exists?(auth_token.id)).to be(true)
  end

  it 'invalidates the MFA token after too many invalid codes' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    token_value = auth_token.token.to_s

    result = nil
    described_class::MAX_FAILED_ATTEMPTS.times do
      result = described_class.run(token_value, '000000')
    end

    expect(result).not_to be_authenticated
    expect(result).to be_failure_limit_exceeded
    expect(AuthToken.exists?(auth_token.id)).to be(false)

    expect do
      described_class.run(token_value, code_at(Time.at(1_700_000_000)))
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')
  end
end
