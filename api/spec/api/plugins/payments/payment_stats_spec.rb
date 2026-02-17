# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::PaymentStats', requires_plugins: :payments do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.support
    seed_payments_sysconfig!(default_currency: 'CZK', conversion_rates: {})
  end

  def estimate_path
    vpath('/payment_stat/estimate_income')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def estimate_obj
    json.dig('response', 'payment_stats') || json.dig('response', 'payment_stat') || json['response'] || {}
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:support) { SpecSeed.support }

  describe 'EstimateIncome' do
    it 'rejects unauthenticated access' do
      json_get estimate_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(user) { json_get estimate_path, payment_stats: { year: 2026, month: 1, select: 'exactly_until', duration: 2 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'returns validation errors for missing required fields' do
      as(admin) { json_get estimate_path, payment_stats: { select: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('year', 'month', 'select', 'duration')
    end

    it 'returns estimated income for deterministic fixtures' do
      user.user_account.update!(monthly_payment: 100, paid_until: Time.utc(2026, 1, 15, 0, 0, 0))
      other_user.user_account.update!(monthly_payment: 250, paid_until: Time.utc(2026, 1, 20, 0, 0, 0))
      support.user_account.update!(monthly_payment: 400, paid_until: Time.utc(2026, 2, 1, 0, 0, 0))

      as(admin) do
        json_get estimate_path, payment_stats: {
          year: 2026,
          month: 1,
          select: 'exactly_until',
          duration: 2
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(estimate_obj['user_count']).to eq(2)
      expect(estimate_obj['estimated_income']).to eq(700)
    end
  end
end
