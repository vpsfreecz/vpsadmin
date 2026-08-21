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

    it 'exports password and MFA state only for the token owner' do
      user.update_columns(
        authentication_generation: 7,
        password_reset: true,
        enable_multi_factor_auth: true
      )
      create_totp_device!(user:)
      create_totp_device!(user:, enabled: false)
      create_totp_device!(user:, confirmed: false)
      user.webauthn_credentials.create!(
        label: 'Metrics passkey',
        external_id: Base64.strict_encode64(SecureRandom.random_bytes(16)),
        public_key: 'metrics-public-key',
        sign_count: 0
      )
      user.webauthn_credentials.create!(
        label: 'Disabled metrics passkey',
        external_id: Base64.strict_encode64(SecureRandom.random_bytes(16)),
        public_key: 'disabled-metrics-public-key',
        sign_count: 0,
        enabled: false
      )
      SpecSeed.other_user.update_column(:authentication_generation, 42)

      request_metrics(access_token: token.access_token)

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('spec_metricsmetrics_version 1.1')
      expect(last_response.body).to include('spec_metricsuser_password_generation 7.0')
      expect(last_response.body).to include('spec_metricsuser_password_reset_required 1.0')
      expect(last_response.body).to include('spec_metricsuser_multi_factor_auth_enabled 1.0')
      expect(last_response.body).to include(
        'spec_metricsuser_multi_factor_auth_method_count{method="totp"} 1.0'
      )
      expect(last_response.body).to include(
        'spec_metricsuser_multi_factor_auth_method_count{method="webauthn"} 1.0'
      )
      expect(last_response.body).not_to include(' 42.0')
      expect(last_response.body).not_to include('user_id=')
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
