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

    it 'localizes rejected access' do
      header 'Accept-Language', 'cs'

      request_metrics

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Přístup odepřen')
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

    context 'with payments plugin metrics', requires_plugins: :payments do
      it 'includes plugin metrics for the token user' do
        user.user_account.update!(monthly_payment: 456, paid_until: Time.local(2026, 6, 1))
        allow(VpsAdmin::API::Metrics).to receive(:plugins)
          .and_return([VpsAdmin::API::Plugins::Payments::Metrics])

        request_metrics(access_token: token.access_token)

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('spec_metricsuser_monthly_payment 456')
        expect(last_response.body).to include('spec_metricsuser_paid_until')
      end
    end
  end
end
