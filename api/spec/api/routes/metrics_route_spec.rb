# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Metrics' do
  before do
    allow(VpsAdmin::API::Metrics).to receive(:plugins).and_return([])
  end

  describe 'GET /metrics' do
    let(:user) { SpecSeed.user }
    let!(:token) { MetricsAccessToken.create_for!(user, 'spec_metrics') }

    def request_metrics(access_token: nil)
      if access_token
        get '/metrics', access_token: access_token
      else
        get '/metrics'
      end
    end

    it 'rejects access without a token' do
      request_metrics

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'rejects access with an invalid token' do
      request_metrics(access_token: 'invalid')

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns Prometheus text with a valid token' do
      request_metrics(access_token: token.access_token)

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/plain')
      expect(last_response.body).not_to be_empty
      expect(last_response.body).to match(/(#\s*HELP|#\s*TYPE|metrics_version|\w+\{.*\}\s+\d+|\w+\s+\d+)/)

      token.reload
      expect(token.use_count).to eq(1)
      expect(token.last_use).not_to be_nil
    end
  end
end
