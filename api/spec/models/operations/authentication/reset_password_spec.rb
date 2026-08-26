# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::ResetPassword do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:auth_token) { create_auth_token!(user:, purpose: 'reset_password') }
  let(:request) do
    build_request(
      ip: '192.0.2.41',
      user_agent: 'Forced reset spec',
      extra_env: {
        'HTTP_CLIENT_IP' => '192.0.2.42',
        'HTTP_X_REAL_IP' => '192.0.2.43'
      }
    )
  end

  before do
    unlock_transaction_signer!
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    user.update!(password_reset: true, lockout: true)
    allow(op).to receive(:resolve_password_change_ptr).with('192.0.2.43')
                                                      .and_return('client.example.test')
  end

  it 'updates the password, clears reset state, and destroys the auth token' do
    other_token = create_auth_token!(user:, purpose: 'mfa')
    token_ids = [auth_token.token_id, other_token.token_id]

    result = nil
    expect do
      result = op.run(auth_token, 'new-password', request:)
    end.to change(MailLog, :count).by(1)

    expect(result.user).to eq(user)
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
    expect(mail.text_plain).to include('192.0.2.43', 'Forced reset spec')
    expect(
      PasswordEventCounter.find_by!(name: 'password_change_forced_reset').event_count
    ).to eq(1)
    expect(result.password_change_log).to eq(PasswordChangeLog.find_by!(user:))
    expect(result.password_change_log).to have_attributes(
      source: 'forced_reset',
      user_session_id: nil,
      client_ip_addr: '192.0.2.43',
      client_ip_ptr: 'client.example.test'
    )
    expect(result.password_change_log.user_agent.agent).to eq('Forced reset spec')
  end

  it 'rejects a token from an older password generation' do
    stale_token = auth_token
    user.set_password('intervening-password')
    user.save!

    expect do
      op.run(stale_token, 'new-password', request:)
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')

    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(
        user.reload.password,
        user.login,
        'intervening-password'
      )
    ).to be(true)
  end

  it 'rejects a reset after destructive lifecycle state is requested' do
    token = auth_token
    original_password = user.password
    record_requested_user_state!(user, :soft_delete)

    expect do
      op.run(token, 'new-password', request:)
    end.to raise_error(VpsAdmin::API::Exceptions::AuthenticationError, 'invalid token')

    expect(user.reload.password).to eq(original_password)
    expect(AuthToken.exists?(token.id)).to be(true)
  end
end
