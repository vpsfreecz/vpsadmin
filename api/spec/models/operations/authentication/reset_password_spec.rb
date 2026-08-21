# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::ResetPassword do
  let(:user) { SpecSeed.user }
  let(:auth_token) { create_auth_token!(user:, purpose: 'reset_password') }
  let(:request) { build_request(ip: '192.0.2.41', user_agent: 'Forced reset spec') }

  before do
    unlock_transaction_signer!
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    user.update!(password_reset: true, lockout: true)
  end

  it 'updates the password, clears reset state, and destroys the auth token' do
    other_token = create_auth_token!(user:, purpose: 'mfa')
    token_ids = [auth_token.token_id, other_token.token_id]

    result = nil
    expect do
      result = described_class.run(auth_token, 'new-password', request:)
    end.to change(MailLog, :count).by(1)

    expect(result).to eq(user)
    expect(user.reload.password_reset).to be(false)
    expect(user.lockout).to be(false)
    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(user.password, user.login, 'new-password')
    ).to be(true)
    expect(AuthToken.exists?(auth_token.id)).to be(false)
    expect(AuthToken.exists?(other_token.id)).to be(false)
    expect(Token.where(id: token_ids)).to be_empty
    mail = MailLog.order(:id).last
    expect(mail.mail_template.name).to eq('user_password_changed')
    expect(mail.text_plain).to include('192.0.2.41', 'Forced reset spec')
    expect(
      PasswordEventCounter.find_by!(name: 'password_change_forced_reset').event_count
    ).to eq(1)
    expect(PasswordChangeLog.find_by!(user:)).to have_attributes(
      source: 'forced_reset',
      user_session_id: nil
    )
  end

  it 'rejects a token from an older password generation' do
    stale_token = auth_token
    user.set_password('intervening-password')
    user.save!

    expect do
      described_class.run(stale_token, 'new-password', request:)
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
