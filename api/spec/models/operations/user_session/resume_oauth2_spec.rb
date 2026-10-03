# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::ResumeOAuth2 do
  let(:user) { SpecSeed.user }
  let(:client) { create_oauth2_client! }

  it 'returns nil and clears currents for an invalid token' do
    User.current = user
    UserSession.current = create_open_session!(user:, auth_type: 'oauth2')

    expect(described_class.run('missing')).to be_nil
    expect(User.current).to be_nil
    expect(UserSession.current).to be_nil
  end

  it 'returns nil for locked or forced-reset users' do
    %i[lockout password_reset].each do |flag|
      user.update!(lockout: false, password_reset: false)
      session = create_open_session!(user:, auth_type: 'oauth2')
      token = session.token.token
      user.update!(flag => true)

      expect(described_class.run(token)).to be_nil
      expect(User.current).to be_nil
      expect(UserSession.current).to be_nil
    end
  end

  it 'accepts suspended users when no reset or lockout is pending' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    token = session.token.token
    user.update!(object_state: :suspended, lockout: false, password_reset: false)

    expect(described_class.run(token)).to eq(session)
    expect(User.current).to eq(user)
  end

  it 'keeps an existing session usable while soft-delete is pending' do
    session = create_open_session!(user:, auth_type: 'oauth2')
    token = session.token.token
    record_requested_user_state!(user, :soft_delete)

    expect(described_class.run(token)).to eq(session)
    expect(User.current).to eq(user)
  end

  it 'renews renewable_auto tokens, extends SSO, and sets currents' do
    session = create_open_session!(
      user:,
      auth_type: 'oauth2',
      token_lifetime: 'renewable_auto',
      token_interval: 3600,
      valid_to: 1.minute.from_now
    )
    sso = create_single_sign_on!(user:, valid_to: 30.seconds.from_now)
    create_oauth2_authorization!(user:, client:, user_session: session, sso:)
    token = session.token.token
    old_valid_to = session.token.valid_to

    result = described_class.run(token)

    expect(result).to eq(session)
    expect(session.reload.request_count).to eq(1)
    expect(session.last_request_at).not_to be_nil
    expect(session.token.valid_to).to be > old_valid_to
    expect(sso.reload.token.valid_to).to eq(session.token.valid_to)
    expect(User.current).to eq(user)
    expect(UserSession.current).to eq(session)
  end

  context 'with a renewable OAuth session' do
    let(:now) { Time.utc(2026, 10, 3, 12) }
    let(:session) do
      create_open_session!(
        user:,
        auth_type: 'oauth2',
        token_lifetime: 'renewable_auto',
        token_interval: 3600,
        valid_to: now + 60
      )
    end
    let(:sso) { create_single_sign_on!(user:, valid_to: now + 30) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    it 'resumes after SSO closure without recreating its token' do
      authorization = create_oauth2_authorization!(user:, client:, user_session: session, sso:)
      sso_token_id = sso.token_id
      access_token_id = session.token_id
      sso.close

      expect(sso.reload.token).to be_nil
      expect(Token.exists?(sso_token_id)).to be(false)
      expect do
        expect(described_class.run(session.token.token)).to eq(session)
      end.not_to change(Token, :count)

      expect(session.reload.closed_at).to be_nil
      expect(session.token_id).to eq(access_token_id)
      expect(session.token.valid_to).to eq(now + 3600)
      expect(session.request_count).to eq(1)
      expect(User.current).to eq(user)
      expect(UserSession.current).to eq(session)
      expect(authorization.reload.user_session).to eq(session)
      expect(authorization.single_sign_on).to eq(sso)
      expect(sso.reload.token).to be_nil
    end

    it 'resumes another valid authorization after its shared SSO is closed' do
      create_oauth2_authorization!(user:, client:, user_session: session, sso:)
      other_session = create_open_session!(user:, auth_type: 'oauth2', valid_to: now + 60)
      other_authorization = create_oauth2_authorization!(
        user:, client: create_oauth2_client!, user_session: other_session, sso:
      )
      sso.authorization_revoked(other_authorization, close_sso: true)

      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 3600)
      expect(User.current).to eq(user)
      expect(UserSession.current).to eq(session)
      expect(other_session.reload.closed_at).to be_nil
      expect(other_authorization.reload.single_sign_on).to eq(sso)
      expect(sso.reload.token).to be_nil
    end

    it 'preserves an SSO expiry later than the renewed access token' do
      sso.token.update!(valid_to: now + 7200)
      create_oauth2_authorization!(user:, client:, user_session: session, sso:)

      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 3600)
      expect(sso.reload.token.valid_to).to eq(now + 7200)
    end

    it 'extends an expired SSO token that is still present' do
      sso.token.update!(valid_to: now - 30)
      create_oauth2_authorization!(user:, client:, user_session: session, sso:)

      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 3600)
      expect(sso.reload.token.valid_to).to eq(session.token.valid_to)
    end

    it 'renews access without an authorization' do
      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 3600)
      expect(User.current).to eq(user)
      expect(UserSession.current).to eq(session)
    end

    it 'renews access without an SSO association' do
      authorization = create_oauth2_authorization!(user:, client:, user_session: session)

      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 3600)
      expect(authorization.reload.single_sign_on).to be_nil
      expect(User.current).to eq(user)
      expect(UserSession.current).to eq(session)
    end

    it 'leaves fixed access expiry unchanged when its SSO is closed' do
      session.update!(token_lifetime: 'fixed')
      create_oauth2_authorization!(user:, client:, user_session: session, sso:)
      sso.close

      expect(described_class.run(session.token.token)).to eq(session)

      expect(session.reload.token.valid_to).to eq(now + 60)
      expect(User.current).to eq(user)
      expect(UserSession.current).to eq(session)
      expect(sso.reload.token).to be_nil
    end

    it 'rejects expired access even when its SSO is closed' do
      create_oauth2_authorization!(user:, client:, user_session: session, sso:)
      sso.close
      session.token.update!(valid_to: now - 1)
      User.current = user
      UserSession.current = session

      expect(described_class.run(session.token.token)).to be_nil

      expect(User.current).to be_nil
      expect(UserSession.current).to be_nil
      expect(session.reload.token.valid_to).to eq(now - 1)
      expect(sso.reload.token).to be_nil
    end

    it 'rejects a closed access session even when its token is valid' do
      session.update!(closed_at: now - 1)
      User.current = user
      UserSession.current = session

      expect(described_class.run(session.token.token)).to be_nil

      expect(User.current).to be_nil
      expect(UserSession.current).to be_nil
      expect(session.reload.token.valid_to).to eq(now + 60)
    end
  end
end
