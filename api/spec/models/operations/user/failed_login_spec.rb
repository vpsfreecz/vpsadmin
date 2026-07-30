# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::User::FailedLogin do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) do
    build_request(
      ip: '198.51.100.51',
      user_agent: 'RSpec/FailedLogin',
      extra_env: { 'HTTP_CLIENT_IP' => '203.0.113.51' }
    )
  end

  before do
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'records request metadata and increments failed_login_count',
     :with_event_delivery do
    expect do
      op.run(user, :password, 'invalid password', request)
    end.to change { user.reload.failed_login_count }.by(1)

    failed = UserFailedLogin.order(:id).last
    expect(failed.user).to eq(user)
    expect(failed.auth_type).to eq('password')
    expect(failed.reason).to eq('invalid password')
    expect(failed.api_ip_addr).to eq('198.51.100.51')
    expect(failed.api_ip_ptr).to eq('ptr.example.test')
    expect(failed.client_ip_addr).to eq('203.0.113.51')
    expect(failed.client_ip_ptr).to eq('ptr.example.test')
    expect(failed.user_agent.agent).to eq('RSpec/FailedLogin')
    expect(failed.client_version).to eq('RSpec/FailedLogin')

    event = Event.find_by!(
      event_type: 'user.login_failed',
      source_class: 'UserFailedLogin',
      source_id: failed.id
    )
    expect(event).to have_attributes(
      user:,
      severity: 'warning',
      ip_addr: '203.0.113.51'
    )
    expect(event.payload).to include(
      'failed_login_id' => failed.id,
      'auth_type' => 'password',
      'reason' => 'invalid password',
      'api_ip_addr' => '198.51.100.51',
      'client_ip_addr' => '203.0.113.51',
      'client_version' => 'RSpec/FailedLogin'
    )
  end
end
