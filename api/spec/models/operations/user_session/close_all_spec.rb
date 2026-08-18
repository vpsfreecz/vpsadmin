# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::CloseAll do
  let(:user) { SpecSeed.user }
  let(:client) { create_oauth2_client! }

  it 'closes all open sessions for a user' do
    sessions = 3.times.map { |i| create_open_session!(user:, auth_type: 'token', label: "token #{i}") }

    described_class.run(user)

    expect(sessions.map { |s| s.reload.closed_at }).to all(be_present)
  end

  it 'honors the except list' do
    kept = create_open_session!(user:, auth_type: 'basic', label: 'keep')
    closed = create_open_session!(user:, auth_type: 'basic', label: 'close')
    kept_sso = create_single_sign_on!(user:)
    closed_sso = create_single_sign_on!(user:)
    kept_authorization = create_oauth2_authorization!(
      user:,
      client:,
      user_session: kept,
      sso: kept_sso
    )
    closed_authorization = create_oauth2_authorization!(
      user:,
      client:,
      user_session: closed,
      sso: closed_sso
    )
    pending_authorization = create_oauth2_authorization!(
      user:,
      client:
    )
    pending_code_id = pending_authorization.code.id

    described_class.run(user, except: [kept])

    expect(kept.reload.closed_at).to be_nil
    expect(closed.reload.closed_at).not_to be_nil
    expect(kept_authorization.reload.code).to be_present
    expect(kept_sso.reload.token).to be_present
    expect(closed_authorization.reload.code).to be_nil
    expect(closed_sso.reload.token).to be_nil
    expect(pending_authorization.reload.code).to be_nil
    expect(Token.exists?(pending_code_id)).to be(false)
  end

  it 'revokes pending OAuth authorizations and single sign-on sessions' do
    sso = create_single_sign_on!(user:)
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      sso:
    )
    code_id = authorization.code.id

    described_class.run(user)

    expect(authorization.reload.code).to be_nil
    expect(Token.exists?(code_id)).to be(false)
    expect(authorization).not_to be_active
    expect(sso.reload.token).to be_nil
  end

  it 'revokes pending authentication tokens' do
    mfa_token = create_auth_token!(user:, purpose: 'mfa')
    password_token = create_auth_token!(user:, purpose: 'reset_password')
    token_ids = [mfa_token.token_id, password_token.token_id]

    described_class.run(user)

    expect(AuthToken.where(id: [mfa_token.id, password_token.id])).to be_empty
    expect(Token.where(id: token_ids)).to be_empty
  end
end
