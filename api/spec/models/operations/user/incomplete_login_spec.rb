# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::User::IncompleteLogin do
  let(:user) { SpecSeed.user }

  it 'records a failed login from an AuthToken' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')

    expect do
      described_class.run(auth_token, :totp, 'authentication token expired')
    end.to change { user.reload.failed_login_count }.by(1)

    failed = UserFailedLogin.order(:id).last
    expect(failed.user).to eq(user)
    expect(failed.auth_type).to eq('totp')
    expect(failed.reason).to eq('authentication token expired')
    expect(failed.api_ip_addr).to eq(auth_token.api_ip_addr)
    expect(failed.client_ip_addr).to eq(auth_token.client_ip_addr)
  end

  it 'records a failed login from a WebauthnChallenge' do
    challenge = create_webauthn_challenge!(user:, type: 'authentication')

    expect do
      described_class.run(challenge, :webauthn, 'authentication challenge expired')
    end.to change { user.reload.failed_login_count }.by(1)

    failed = UserFailedLogin.order(:id).last
    expect(failed.user).to eq(user)
    expect(failed.auth_type).to eq('webauthn')
    expect(failed.reason).to eq('authentication challenge expired')
    expect(failed.api_ip_addr).to eq(challenge.api_ip_addr)
    expect(failed.client_ip_addr).to eq(challenge.client_ip_addr)
  end

  it 'no-ops when the associated user is gone' do
    auth_token = create_auth_token!(user:, purpose: 'mfa')
    auth_token.update_column(:user_id, User.maximum(:id).to_i + 1000)
    auth_token.association(:user).reset

    expect do
      described_class.run(auth_token, :totp, 'authentication token expired')
    end.not_to change(UserFailedLogin, :count)
  end
end
