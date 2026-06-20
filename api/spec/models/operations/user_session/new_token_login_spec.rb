# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::NewTokenLogin do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.62', user_agent: 'RSpec/TokenLogin') }

  before do
    user.reload.update!(
      lockout: false,
      password_reset: false,
      enable_new_login_notification: false
    )
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'performs User::Login, opens a token session, and sets current session' do
    allow(VpsAdmin::API::Operations::User::Login).to receive(:run).and_call_original
    allow(VpsAdmin::API::NotificationEvents).to receive(:run_chain)

    session = op.run(user, request, 'fixed', 3600, ['all'])

    expect(VpsAdmin::API::Operations::User::Login).to have_received(:run).with(user, request)
    expect(VpsAdmin::API::NotificationEvents).not_to have_received(:run_chain)
    expect(session).to be_persisted
    expect(session.auth_type).to eq('token')
    expect(session.token).to be_present
    expect(session.scope).to eq(['all'])
    expect(UserSession.current).to eq(session)
  end

  it 'fires NewToken only when notifications are enabled' do
    user.update!(enable_new_login_notification: true)

    allow(VpsAdmin::API::NotificationEvents).to receive(:run_chain)

    op.run(user, request, 'fixed', 3600, ['all'])

    expect(VpsAdmin::API::NotificationEvents).to have_received(:run_chain).with(
      TransactionChains::User::NewToken,
      args: [kind_of(UserSession)]
    )
  end
end
