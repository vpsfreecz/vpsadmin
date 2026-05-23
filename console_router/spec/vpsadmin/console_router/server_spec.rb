# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::ConsoleRouter::Server do
  include Rack::Test::Methods

  def app
    described_class
  end

  after do
    described_class.set(:router, nil)
    described_class.set(:router_factory, described_class::RouterFactory.new)
  end

  describe 'GET /console/:vps_id' do
    it 'lazily initializes the router with the configured factory' do
      router = instance_spy(VpsAdmin::ConsoleRouter::Router, check_session: false)
      factory = instance_spy(described_class::RouterFactory, call: router)

      described_class.set(:router_factory, factory)

      get '/console/101', session: 'bad-token'

      expect(last_response).to be_ok
      expect(factory).to have_received(:call).once
      expect(described_class.settings.router).to eq(router)
    end

    it 'renders the console page for a valid session' do
      router = instance_spy(
        VpsAdmin::ConsoleRouter::Router,
        api_url: 'http://api.example.test',
        check_session: true
      )

      described_class.set(:router, router)

      get '/console/101',
          session: 'session-token',
          auth_type: 'token',
          auth_token: 'auth-token'

      expect(last_response).to be_ok
      expect(router).to have_received(:check_session).with(101, 'session-token')
      expect(last_response.body).to include('new VpsAdminConsole')
      expect(last_response.body).to include('101')
      expect(last_response.body).to include("'session-token'")
    end

    it 'does not render legacy API credential query params' do
      router = instance_spy(
        VpsAdmin::ConsoleRouter::Router,
        api_url: 'http://api.example.test',
        check_session: true
      )

      described_class.set(:router, router)

      get '/console/101',
          session: 'session-token',
          auth_type: 'token',
          auth_token: 'secret-api-token'

      expect(last_response).to be_ok
      expect(router).to have_received(:check_session).with(101, 'session-token')
      expect(last_response.body).not_to include('secret-api-token')
      expect(last_response.body).not_to include('auth_token')
      expect(last_response.body).not_to include('auth_type')
    end

    it 'rejects an invalid session' do
      router = instance_spy(VpsAdmin::ConsoleRouter::Router, check_session: false)

      described_class.set(:router, router)

      get '/console/101', session: 'bad-token'

      expect(last_response).to be_ok
      expect(router).to have_received(:check_session).with(101, 'bad-token')
      expect(last_response.body).to eq('Access denied, invalid session')
    end
  end

  describe 'POST /console/feed/:vps_id' do
    it 'returns base64 encoded console output for a valid session' do
      router = instance_spy(
        VpsAdmin::ConsoleRouter::Router,
        read_write_console: "output\n"
      )

      described_class.set(:router, router)

      post '/console/feed/101',
           session: 'session-token',
           keys: "ls\n",
           width: '80',
           height: '25'

      response = JSON.parse(last_response.body)

      expect(last_response).to be_ok
      expect(router).to have_received(:read_write_console)
        .with(101, 'session-token', "ls\n", 80, 25)
      expect(response.fetch('session')).to be(true)
      expect(Base64.decode64(response.fetch('data'))).to eq("output\n")
    end

    it 'returns the invalid-session response when routing fails' do
      router = instance_spy(
        VpsAdmin::ConsoleRouter::Router,
        read_write_console: nil
      )

      described_class.set(:router, router)

      post '/console/feed/101',
           session: 'bad-token',
           width: '80',
           height: '25'

      response = JSON.parse(last_response.body)

      expect(last_response).to be_ok
      expect(router).to have_received(:read_write_console)
        .with(101, 'bad-token', nil, 80, 25)
      expect(response).to eq(
        'data' => 'Access denied, invalid session',
        'session' => nil
      )
    end
  end
end
