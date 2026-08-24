# frozen_string_literal: true

RSpec.describe PasswordRecovery do
  let(:user) { create_lifecycle_user! }

  def create_recovery
    recovery_request = PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en'
    )
    recovery_request.password_recoveries.create!(
      user:,
      outcome: :recoverable,
      email_snapshot: user.email,
      email_token_digest: described_class.digest_token(described_class.generate_token),
      email_expires_at: 1.hour.from_now
    )
  end

  it 'invalidates outstanding recovery links when the password changes' do
    recovery = create_recovery

    user.set_password('a-different-secret')
    user.save!

    expect(recovery.reload.invalidated_at).to be_present
  end

  it 'invalidates active recovery when crossing the privileged-account boundary' do
    promoted = create_recovery
    user.update!(level: 21)

    expect(promoted.reload.invalidated_at).to be_present

    demoted = create_recovery
    user.update!(level: 1)

    expect(demoted.reload.invalidated_at).to be_present
  end

  it 'keeps active recovery when changing between ordinary user levels' do
    recovery = create_recovery

    user.update!(level: 2)

    expect(recovery.reload.invalidated_at).to be_nil
  end

  it 'records the exact factor used for MFA verification' do
    totp = create_totp_device!(user:)
    passkey = WebauthnCredential.create!(
      user:,
      label: 'Spec passkey',
      external_id: SecureRandom.hex(16),
      public_key: 'spec-public-key',
      sign_count: 0
    )
    recovery = create_recovery

    recovery.verify_mfa_with!(totp)
    expect(recovery).to have_attributes(
      verified_totp_device_id: totp.id,
      verified_webauthn_credential_id: nil
    )

    recovery.verify_mfa_with!(passkey)
    expect(recovery).to have_attributes(
      verified_totp_device_id: nil,
      verified_webauthn_credential_id: passkey.id
    )
  end

  it 'does not trust an MFA timestamp without an exact verified factor' do
    recovery = create_recovery
    recovery.update!(mfa_verified_at: Time.current)

    expect(recovery).not_to be_mfa_verified
  end

  it 'invalidates active recoveries and MFA tokens when account MFA is disabled' do
    user.update!(enable_multi_factor_auth: true)
    recovery = create_recovery
    auth_token = create_auth_token!(user:, purpose: 'mfa')

    user.update!(enable_multi_factor_auth: false)

    expect(recovery.reload.invalidated_at).to be_present
    expect(AuthToken.exists?(auth_token.id)).to be(false)
  end

  it 'exchanges an email token for a short-lived session token only once' do
    recovery = create_recovery

    session_token = recovery.consume_email_token!

    expect(described_class.find_by_session_token(session_token)).to eq(recovery)
    expect(recovery.email_token_usable?).to be(false)
    expect(recovery.session_expires_at).to be_within(2.seconds).of(
      described_class::SESSION_LIFETIME.from_now
    )
    expect { recovery.consume_email_token! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects completed and invalidated state after a row is reloaded' do
    completed = create_recovery
    invalidated = create_recovery
    completed.update!(completed_at: Time.current)
    invalidated.update!(invalidated_at: Time.current)

    expect(completed.email_token_usable?).to be(false)
    expect(invalidated.email_token_usable?).to be(false)

    [completed, invalidated].each do |recovery|
      recovery.update_columns(
        email_consumed_at: Time.current,
        session_token_digest: described_class.digest_token(described_class.generate_token),
        session_expires_at: 15.minutes.from_now
      )
      expect(recovery.reload.session_usable?).to be(false)
    end
  end
end
