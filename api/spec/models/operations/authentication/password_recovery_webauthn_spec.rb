# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::PasswordRecoveryWebauthn do
  it 'commits challenge consumption for recognized malformed assertions',
     :no_transaction do
    user = create_lifecycle_user!
    user.update!(enable_multi_factor_auth: true, enable_oauth2_auth: true)
    raw_id = "malformed-passkey-#{SecureRandom.hex(6)}"
    credential = WebauthnCredential.create!(
      user:,
      label: 'Malformed assertion passkey',
      external_id: Base64.strict_encode64(raw_id),
      public_key: 'unused-for-malformed-assertion',
      sign_count: 0
    )
    recovery_request = PasswordRecoveryRequest.create!(
      recipient_email: user.email,
      locale: 'en'
    )
    encoded_id = Base64.urlsafe_encode64(raw_id, padding: false)
    assertions = [
      {
        type: 'wrong-type',
        id: encoded_id,
        rawId: encoded_id,
        response: {
          authenticatorData: '',
          clientDataJSON: '',
          signature: ''
        }
      },
      {
        type: 'public-key',
        id: encoded_id,
        rawId: encoded_id,
        response: {
          authenticatorData: '',
          clientDataJSON: Base64.urlsafe_encode64('not-json', padding: false),
          signature: ''
        }
      },
      {
        type: 'public-key',
        id: encoded_id,
        rawId: encoded_id,
        response: {
          authenticatorData: '',
          clientDataJSON: Base64.urlsafe_encode64('{}', padding: false),
          signature: ''
        }
      }
    ]

    assertions.each do |assertion|
      recovery = recovery_request.password_recoveries.create!(
        user:,
        outcome: :recoverable,
        email_snapshot: user.email,
        email_token_digest: nil,
        email_expires_at: 1.hour.from_now,
        email_consumed_at: Time.current,
        session_token_digest: PasswordRecovery.digest_token(SecureRandom.hex(16)),
        session_expires_at: 15.minutes.from_now
      )
      challenge = create_webauthn_challenge!(user:, type: :authentication)
      challenge.update!(password_recovery: recovery)
      result = described_class.run(
        recovery,
        challenge,
        assertion,
        build_request
      )

      expect(result).not_to be_authenticated
      expect(result.error).to be_a(ArgumentError)
      expect(WebauthnChallenge.exists?(challenge.id)).to be(false)
    end
  ensure
    recovery_request&.destroy! if recovery_request && PasswordRecoveryRequest.exists?(recovery_request.id)
    credential&.destroy! if credential && WebauthnCredential.exists?(credential.id)
    user&.delete if user && User.exists?(user.id)
  end
end
