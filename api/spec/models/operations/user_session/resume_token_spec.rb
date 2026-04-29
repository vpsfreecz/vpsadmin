# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::ResumeToken do
  let(:user) { SpecSeed.user }

  it 'returns nil and clears currents for an invalid token' do
    User.current = user
    UserSession.current = create_open_session!(user:, auth_type: 'token')

    expect(described_class.run('missing')).to be_nil
    expect(User.current).to be_nil
    expect(UserSession.current).to be_nil
  end

  it 'returns nil and clears currents for a closed session' do
    session = create_open_session!(user:, auth_type: 'token')
    token = session.token.token
    session.close!
    User.current = user
    UserSession.current = session

    expect(described_class.run(token)).to be_nil
    expect(User.current).to be_nil
    expect(UserSession.current).to be_nil
  end

  it 'returns nil and clears currents for inactive user states' do
    session = create_open_session!(user:, auth_type: 'token')
    token = session.token.token
    user.update!(object_state: :soft_delete)
    User.current = user
    UserSession.current = session

    expect(described_class.run(token)).to be_nil
    expect(User.current).to be_nil
    expect(UserSession.current).to be_nil
  end

  it 'increments request counters, renews renewable_auto tokens, and sets currents' do
    session = create_open_session!(
      user:,
      auth_type: 'token',
      token_lifetime: 'renewable_auto',
      token_interval: 3600,
      valid_to: 1.minute.from_now
    )
    token = session.token.token
    old_valid_to = session.token.valid_to

    result = described_class.run(token)

    expect(result).to eq(session)
    expect(session.reload.request_count).to eq(1)
    expect(session.last_request_at).not_to be_nil
    expect(session.token.valid_to).to be > old_valid_to
    expect(user.reload.last_request_at).not_to be_nil
    expect(User.current).to eq(user)
    expect(UserSession.current).to eq(session)
  end
end
