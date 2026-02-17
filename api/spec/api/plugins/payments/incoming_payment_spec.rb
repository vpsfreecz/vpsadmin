# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::IncomingPayment', requires_plugins: :payments do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    seed_payments_sysconfig!(default_currency: 'CZK', conversion_rates: {})
  end

  def index_path
    vpath('/incoming_payments')
  end

  def show_path(id)
    vpath("/incoming_payments/#{id}")
  end

  def update_path(id)
    show_path(id)
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def incoming_payments
    json.dig('response', 'incoming_payments') || []
  end

  def incoming_payment
    json.dig('response', 'incoming_payment') || json['response']
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

  let!(:payment_old) do
    ::IncomingPayment.create!(
      transaction_id: 'spec-tx-1',
      state: :queued,
      date: Date.new(2026, 1, 15),
      amount: 100,
      currency: 'CZK',
      transaction_type: 'spec',
      created_at: Time.utc(2026, 1, 15, 10, 0, 0)
    )
  end

  let!(:payment_mid) do
    ::IncomingPayment.create!(
      transaction_id: 'spec-tx-2',
      state: :processed,
      date: Date.new(2026, 1, 16),
      amount: 200,
      currency: 'CZK',
      transaction_type: 'spec',
      created_at: Time.utc(2026, 1, 16, 10, 0, 0)
    )
  end

  let!(:payment_new) do
    ::IncomingPayment.create!(
      transaction_id: 'spec-tx-3',
      state: :queued,
      date: Date.new(2026, 1, 16),
      amount: 300,
      currency: 'CZK',
      transaction_type: 'spec',
      created_at: Time.utc(2026, 1, 16, 11, 0, 0)
    )
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists incoming payments for admin in date/id desc order' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = incoming_payments.map { |row| row['id'].to_i }
      expect(ids).to eq([payment_new.id, payment_mid.id, payment_old.id])

      row = incoming_payments.first
      expect(row).to include('id', 'transaction_id', 'state', 'date', 'amount', 'currency')
    end

    it 'filters by state' do
      as(admin) { json_get index_path, incoming_payment: { state: 'queued' } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = incoming_payments.map { |row| row['id'].to_i }
      expect(ids).to eq([payment_new.id, payment_old.id])
      expect(incoming_payments.all? { |row| row['state'] == 'queued' }).to be(true)
    end
  end

  describe 'Show' do
    it 'shows a payment for admin' do
      as(admin) { json_get show_path(payment_old.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(incoming_payment['id'].to_i).to eq(payment_old.id)
      expect(incoming_payment['transaction_id']).to eq('spec-tx-1')
    end

    it 'returns 404 for missing payment' do
      missing = payment_new.id + 10_000
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'updates payment state for admin' do
      as(admin) { json_put update_path(payment_old.id), incoming_payment: { state: 'ignored' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(incoming_payment['state']).to eq('ignored')
      expect(::IncomingPayment.find(payment_old.id).state).to eq('ignored')
    end

    it 'returns validation error for missing state' do
      as(admin) { json_put update_path(payment_old.id), incoming_payment: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('state')
    end
  end
end
