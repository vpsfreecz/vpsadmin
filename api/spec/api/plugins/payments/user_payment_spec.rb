# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserPayment', requires_plugins: :payments do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    seed_payments_sysconfig!(default_currency: 'CZK', conversion_rates: {})
    SpecSeed.user.user_account.update!(monthly_payment: 100, paid_until: nil)
    SpecSeed.other_user.user_account.update!(monthly_payment: 100, paid_until: nil)
  end

  def index_path
    vpath('/user_payments')
  end

  def show_path(id)
    vpath("/user_payments/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def user_payments
    json.dig('response', 'user_payments') || []
  end

  def user_payment
    json.dig('response', 'user_payment') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def ensure_node_current_status(node = SpecSeed.node)
    NodeCurrentStatus.find_or_create_by!(node:) do |st|
      st.vpsadmin_version = 'test'
      st.kernel = 'test'
      st.update_count = 1
    end
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def build_user_payment(user:, accounted_by:, amount:, from_date:, to_date:, incoming_payment: nil)
    payment = ::UserPayment.new(
      user: user,
      accounted_by: accounted_by,
      amount: amount,
      from_date: from_date,
      to_date: to_date,
      incoming_payment: incoming_payment,
      created_at: from_date
    )
    payment.save!
    payment
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  describe 'Index' do
    let!(:user_payment_row) do
      build_user_payment(
        user: user,
        accounted_by: admin,
        amount: 100,
        from_date: Time.utc(2026, 1, 1, 0, 0, 0),
        to_date: Time.utc(2026, 2, 1, 0, 0, 0)
      )
    end

    let!(:other_payment_row) do
      build_user_payment(
        user: other_user,
        accounted_by: admin,
        amount: 200,
        from_date: Time.utc(2026, 1, 1, 0, 0, 0),
        to_date: Time.utc(2026, 3, 1, 0, 0, 0)
      )
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns only own payments for normal user' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = user_payments.map { |row| row['id'].to_i }
      expect(ids).to contain_exactly(user_payment_row.id)
    end

    it 'ignores user filters for normal users' do
      as(user) { json_get index_path, user_payment: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = user_payments.map { |row| row['id'].to_i }
      expect(ids).to contain_exactly(user_payment_row.id)
    end

    it 'lists all payments for admin' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = user_payments.map { |row| row['id'].to_i }
      expect(ids).to contain_exactly(user_payment_row.id, other_payment_row.id)
    end

    it 'allows admin to filter by user' do
      as(admin) { json_get index_path, user_payment: { user: user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = user_payments.map { |row| row['id'].to_i }
      expect(ids).to contain_exactly(user_payment_row.id)
    end
  end

  describe 'Show' do
    let!(:user_payment_row) do
      build_user_payment(
        user: user,
        accounted_by: admin,
        amount: 100,
        from_date: Time.utc(2026, 1, 1, 0, 0, 0),
        to_date: Time.utc(2026, 2, 1, 0, 0, 0)
      )
    end

    let!(:other_payment_row) do
      build_user_payment(
        user: other_user,
        accounted_by: admin,
        amount: 200,
        from_date: Time.utc(2026, 1, 1, 0, 0, 0),
        to_date: Time.utc(2026, 3, 1, 0, 0, 0)
      )
    end

    it 'allows normal users to show their own payment' do
      as(user) { json_get show_path(user_payment_row.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_payment['id'].to_i).to eq(user_payment_row.id)
    end

    it 'rejects normal users from showing other payments' do
      as(user) { json_get show_path(other_payment_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any payment' do
      as(admin) { json_get show_path(other_payment_row.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_payment['id'].to_i).to eq(other_payment_row.id)
    end
  end

  describe 'Create' do
    let(:payment_user) { other_user }

    before do
      ensure_signer_unlocked!
      ensure_node_current_status
      payment_user.user_account.update!(monthly_payment: 100, paid_until: nil)
      payment_user.update!(mailer_enabled: false)
    end

    it 'rejects unauthenticated access' do
      json_post index_path, user_payment: { user: payment_user.id, amount: 200 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post index_path, user_payment: { user: payment_user.id, amount: 200 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'rejects missing amount and incoming payment' do
      as(admin) { json_post index_path, user_payment: { user: payment_user.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg.to_s).to include('Provide amount or incoming payment')
    end

    it 'rejects invalid amount multiple' do
      as(admin) { json_post index_path, user_payment: { user: payment_user.id, amount: 150 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('amount')
    end

    it 'creates a manual payment for admin' do
      before_count = ::UserPayment.count

      as(admin) { json_post index_path, user_payment: { user: payment_user.id, amount: 200 } }

      expect_status(200)
      expect(json['status']).to be(true), "message=#{msg} errors=#{response_errors}"
      expect(::UserPayment.count - before_count).to eq(1)

      payment = ::UserPayment.where(user: payment_user).order('id DESC').first
      expect(payment).not_to be_nil
      expect(payment.accounted_by_id).to eq(admin.id)
      expect(payment.amount).to eq(200)

      user_account = payment_user.user_account.reload
      expect(user_account.paid_until).not_to be_nil
      expect(user_account.paid_until.to_i).to eq(payment.to_date.to_i)

      expect(action_state_id).to be_nil
    end

    it 'creates a payment from incoming_payment for admin' do
      income = ::IncomingPayment.create!(
        transaction_id: 'spec-tx-income-1',
        state: :queued,
        date: Date.new(2026, 1, 10),
        amount: 300,
        currency: 'CZK',
        transaction_type: 'spec',
        created_at: Time.utc(2026, 1, 10, 12, 0, 0)
      )

      before_count = ::UserPayment.count

      as(admin) { json_post index_path, user_payment: { user: payment_user.id, incoming_payment: income.id } }

      expect_status(200)
      expect(json['status']).to be(true), "message=#{msg} errors=#{response_errors}"
      expect(::UserPayment.count - before_count).to eq(1)

      payment = ::UserPayment.find_by!(incoming_payment_id: income.id)
      expect(payment.amount).to eq(300)
      expect(payment.user_id).to eq(payment_user.id)
      expect(::IncomingPayment.find(income.id).state).to eq('processed')
    end

    it 'rejects duplicate incoming payment assignment' do
      income = ::IncomingPayment.create!(
        transaction_id: 'spec-tx-income-2',
        state: :queued,
        date: Date.new(2026, 1, 11),
        amount: 300,
        currency: 'CZK',
        transaction_type: 'spec',
        created_at: Time.utc(2026, 1, 11, 12, 0, 0)
      )

      build_user_payment(
        user: payment_user,
        accounted_by: admin,
        amount: 300,
        from_date: Time.utc(2026, 1, 1, 0, 0, 0),
        to_date: Time.utc(2026, 4, 1, 0, 0, 0),
        incoming_payment: income
      )

      as(admin) { json_post index_path, user_payment: { user: payment_user.id, incoming_payment: income.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg.to_s).to include('already assigned')
    end
  end
end
