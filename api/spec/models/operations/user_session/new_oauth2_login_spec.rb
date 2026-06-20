# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::NewOAuth2Login do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.64', user_agent: 'RSpec/OAuth2Login') }
  let(:client) { create_oauth2_client! }

  before do
    user.reload.update!(
      lockout: false,
      password_reset: false,
      enable_new_login_notification: false
    )
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'opens an oauth2 session, marks an unknown device as known, and sets current session' do
    user_device = create_user_device!(user:, known: false)
    authorization = create_oauth2_authorization!(user:, client:, user_device:)

    session = op.run(authorization, request, 'fixed', 900, ['all'])

    expect(session).to be_persisted
    expect(session.auth_type).to eq('oauth2')
    expect(session.token).to be_present
    expect(UserSession.current).to eq(session)
    expect(user_device.reload.known).to be(true)
  end

  it 'fires NewLogin only for unknown devices with notifications enabled' do
    user.update!(enable_new_login_notification: true)
    user_device = create_user_device!(user:, known: false)
    authorization = create_oauth2_authorization!(user:, client:, user_device:)

    allow(VpsAdmin::API::NotificationEvents).to receive(:run_chain)

    op.run(authorization, request, 'fixed', 900, ['all'])

    expect(VpsAdmin::API::NotificationEvents).to have_received(:run_chain).with(
      TransactionChains::User::NewLogin,
      args: [kind_of(UserSession), authorization]
    )
  end

  it 'does not fire NewLogin for a known device' do
    user.update!(enable_new_login_notification: true)
    user_device = create_user_device!(user:, known: true)
    authorization = create_oauth2_authorization!(user:, client:, user_device:)

    allow(VpsAdmin::API::NotificationEvents).to receive(:run_chain)

    op.run(authorization, request, 'fixed', 900, ['all'])

    expect(VpsAdmin::API::NotificationEvents).not_to have_received(:run_chain)
  end
end
