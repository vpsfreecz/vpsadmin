# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::Close do
  let(:user) { SpecSeed.user }
  let(:client) { create_oauth2_client!(issue_refresh_token: true) }

  it 'closes the session, revokes tokens, and closes attached OAuth2 state' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    access_token_id = session.token.id
    sso = create_single_sign_on!(user:)
    authorization = create_oauth2_authorization!(
      user:,
      client:,
      user_session: session,
      sso:,
      refresh_valid_to: 1.hour.from_now
    )
    refresh_token_id = authorization.refresh_token.id
    authorization.code.destroy!
    authorization.update!(code: nil)

    described_class.run(session)

    expect(session.reload.closed_at).not_to be_nil
    expect(session.token).to be_nil
    expect(Token.exists?(access_token_id)).to be(false)
    expect(authorization.reload.refresh_token).to be_nil
    expect(Token.exists?(refresh_token_id)).to be(false)
    expect(sso.reload.token).to be_nil
  end

  it 'closes stale single sign-on records' do
    session = create_open_session!(user:, auth_type: 'basic')
    stale_sso = create_single_sign_on!(user:, valid_to: 1.minute.ago)

    described_class.run(session)

    expect(stale_sso.reload.token).to be_nil
  end
end
