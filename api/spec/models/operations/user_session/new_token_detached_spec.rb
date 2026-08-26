# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::NewTokenDetached do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }
  let(:request) { build_request(ip: '198.51.100.63', user_agent: 'RSpec/Detached') }

  before do
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'opens a detached token session without setting current session' do
    session = op.run(
      user:,
      admin:,
      request:,
      token_lifetime: 'fixed',
      token_interval: 3600,
      scope: ['vps#show'],
      label: 'Admin token'
    )

    expect(session.user).to eq(user)
    expect(session.admin).to eq(admin)
    expect(session.auth_type).to eq('token')
    expect(session.label).to eq('Admin token')
    expect(session.scope).to eq(['vps#show'])
    expect(session.token).to be_present
    expect(UserSession.current).to be_nil
  end

  it 'does not issue a token after a destructive lifecycle state is requested' do
    record_requested_user_state!(user, :soft_delete)
    session_count = UserSession.count
    token_count = Token.count

    expect do
      op.run(
        user:,
        admin:,
        request:,
        token_lifetime: 'fixed',
        token_interval: 3600,
        scope: ['vps#show'],
        label: 'Rejected admin token'
      )
    end.to raise_error(ResourceLocked, 'user lifecycle change is pending')

    expect(UserSession.count).to eq(session_count)
    expect(Token.count).to eq(token_count)
  end
end
