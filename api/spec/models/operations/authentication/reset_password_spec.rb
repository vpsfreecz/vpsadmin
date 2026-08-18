# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::ResetPassword do
  let(:user) { SpecSeed.user }
  let(:auth_token) { create_auth_token!(user:, purpose: 'reset_password') }

  before do
    user.update!(password_reset: true, lockout: true)
  end

  it 'updates the password, clears reset state, and destroys the auth token' do
    other_token = create_auth_token!(user:, purpose: 'mfa')
    token_ids = [auth_token.token_id, other_token.token_id]

    result = described_class.run(auth_token, 'new-password')

    expect(result).to eq(user)
    expect(user.reload.password_reset).to be(false)
    expect(user.lockout).to be(false)
    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(user.password, user.login, 'new-password')
    ).to be(true)
    expect(AuthToken.exists?(auth_token.id)).to be(false)
    expect(AuthToken.exists?(other_token.id)).to be(false)
    expect(Token.where(id: token_ids)).to be_empty
  end

  it 'rejects a token from an older password generation' do
    stale_token = auth_token
    user.set_password('intervening-password')
    user.save!

    expect do
      described_class.run(stale_token, 'new-password')
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')

    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(
        user.reload.password,
        user.login,
        'intervening-password'
      )
    ).to be(true)
  end
end
