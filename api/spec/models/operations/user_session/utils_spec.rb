# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::Utils do
  let(:host_class) do
    Class.new do
      include VpsAdmin::API::Operations::UserSession::Utils
    end
  end
  let(:helper) { host_class.new }
  let(:user) { SpecSeed.user }
  let(:request) do
    build_request(
      ip: '198.51.100.60',
      user_agent: 'RSpec/Utils',
      extra_env: { 'HTTP_X_REAL_IP' => '203.0.113.60' }
    )
  end

  before do
    stub_ptr_lookup!(helper, ptr: 'ptr.example.test')
  end

  it 'builds a token session with request metadata, label, and scope' do
    session = helper.open_session(
      user:,
      request:,
      auth_type: :token,
      scope: ['vps#show'],
      generate_token: true,
      token_lifetime: 'renewable_auto',
      token_interval: 3600,
      label: 'Spec token'
    )

    expect(session).to be_persisted
    expect(session.auth_type).to eq('token')
    expect(session.scope).to eq(['vps#show'])
    expect(session.label).to eq('Spec token')
    expect(session.api_ip_addr).to eq('198.51.100.60')
    expect(session.api_ip_ptr).to eq('ptr.example.test')
    expect(session.client_ip_addr).to eq('203.0.113.60')
    expect(session.client_ip_ptr).to eq('ptr.example.test')
    expect(session.user_agent.agent).to eq('RSpec/Utils')
    expect(session.client_version).to eq('RSpec/Utils')
    expect(session.token).to be_present
    expect(session.token_str).to eq(session.token.token)
  end

  it 'raises when a non-permanent token lifetime has no interval' do
    expect do
      helper.open_session(
        user:,
        request:,
        auth_type: :token,
        scope: ['all'],
        generate_token: true,
        token_lifetime: 'fixed',
        token_interval: nil
      )
    end.to raise_error(ArgumentError, 'missing token_interval for non-permanent token_lifetime')
  end

  it 'keeps token valid_to nil for permanent sessions' do
    session = helper.open_session(
      user:,
      request:,
      auth_type: :token,
      scope: ['all'],
      generate_token: true,
      token_lifetime: 'permanent',
      token_interval: nil
    )

    expect(session.token_lifetime).to eq('permanent')
    expect(session.token.valid_to).to be_nil
  end
end
