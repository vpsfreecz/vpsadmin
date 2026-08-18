# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::PasswordRecoveryPolicy do
  let(:request) { build_request(user_agent: 'Password recovery policy spec') }
  let(:user) do
    create_lifecycle_user!.tap do |record|
      record.update!(
        enable_multi_factor_auth: true,
        enable_oauth2_auth: true
      )
    end
  end

  it 'reports the effective configured recovery methods' do
    create_totp_device!(user:, confirmed: false)
    create_totp_device!(user:, confirmed: true)
    user.webauthn_credentials.create!(
      label: 'Recovery passkey',
      external_id: 'password-recovery-policy-passkey',
      public_key: 'spec-public-key',
      sign_count: 0
    )

    result = described_class.run(user, request)

    expect(result).to be_eligible
    expect(result).to be_effective_mfa
    expect(result.mfa_methods).to contain_exactly(:totp, :webauthn)
  end

  it 'rejects accounts disabled by the shared login policy' do
    create_totp_device!(user:)
    user.update!(lockout: true)

    result = described_class.run(user, request)

    expect(result).not_to be_eligible
  end

  it 'does not treat an unconfirmed TOTP device as effective MFA' do
    create_totp_device!(user:, confirmed: false)

    result = described_class.run(user, request)

    expect(result).to be_eligible
    expect(result).not_to be_effective_mfa
    expect(result.mfa_methods).to be_empty
  end
end
