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
end
