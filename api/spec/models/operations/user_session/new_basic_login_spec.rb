# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::NewBasicLogin do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.61', user_agent: 'RSpec/BasicLogin') }

  before do
    user.reload.update!(lockout: false, password_reset: false)
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'performs User::Login, opens and immediately closes a basic session' do
    allow(VpsAdmin::API::Operations::User::Login).to receive(:run).and_call_original

    session = op.run(user, request)

    expect(VpsAdmin::API::Operations::User::Login).to have_received(:run).with(user, request)
    expect(session).to be_persisted
    expect(session.auth_type).to eq('basic')
    expect(session.token).to be_nil
    expect(session.closed_at).not_to be_nil
    expect(UserSession.current).to eq(session)
  end
end
