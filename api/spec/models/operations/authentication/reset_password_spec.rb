# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::ResetPassword do
  let(:user) { SpecSeed.user }
  let(:auth_token) { create_auth_token!(user:, purpose: 'reset_password') }

  before do
    user.update!(password_reset: true, lockout: true)
  end

  it 'updates the password, clears reset state, and destroys the auth token' do
    result = described_class.run(auth_token, 'new-password')

    expect(result).to eq(user)
    expect(user.reload.password_reset).to be(false)
    expect(user.lockout).to be(false)
    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(user.password, user.login, 'new-password')
    ).to be(true)
    expect(AuthToken.exists?(auth_token.id)).to be(false)
  end
end
