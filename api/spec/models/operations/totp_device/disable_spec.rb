# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Disable do
  def create_verified_recovery(user, device)
    request = PasswordRecoveryRequest.create!(recipient_email: user.email, locale: 'en')
    request.password_recoveries.create!(
      user:,
      outcome: :recoverable,
      email_snapshot: user.email,
      email_token_digest: PasswordRecovery.digest_token(SecureRandom.hex(16)),
      email_expires_at: 1.hour.from_now
    ).tap { |recovery| recovery.verify_mfa_with!(device) }
  end

  it 'disables the device' do
    device = create_totp_device!(user: SpecSeed.user, confirmed: true, enabled: true)

    result = described_class.run(device)

    expect(result).to eq(device)
    expect(device.reload.enabled).to be(false)
  end

  it 'invalidates only recoveries verified with the disabled device' do
    user = create_lifecycle_user!
    disabled = create_totp_device!(user:)
    unrelated = create_totp_device!(user:)
    invalidated = create_verified_recovery(user, disabled)
    preserved = create_verified_recovery(user, unrelated)

    described_class.run(disabled)

    expect(invalidated.reload.invalidated_at).to be_present
    expect(preserved.reload.invalidated_at).to be_nil
  end
end
