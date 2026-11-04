# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserAccount', requires_plugins: :payments do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    seed_payments_sysconfig!(default_currency: 'CZK', conversion_rates: {})
  end

  def index_path
    vpath('/user_accounts')
  end

  def show_path(id)
    vpath("/user_accounts/#{id}")
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

  def user_accounts
    json.dig('response', 'user_accounts') || []
  end

  def user_account
    json.dig('response', 'user_account') || json['response']
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

    it 'lists user accounts for admin' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = user_accounts.map { |row| row['id'].to_i }
      expect(ids).to include(user.id, other_user.id)

      row = user_accounts.find { |r| r['id'].to_i == user.id }
      expect(row).to include('id', 'monthly_payment', 'paid_until')
    end
  end

  describe 'Show' do
    it 'shows a user account for admin' do
      as(admin) { json_get show_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_account['id'].to_i).to eq(user.id)
    end

    it 'returns 404 for missing account' do
      missing = user.id + 10_000
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'updates monthly_payment for admin' do
      as(admin) { json_put update_path(user.id), user_account: { monthly_payment: '150' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_account['monthly_payment'].to_i).to eq(150)
      expect(::UserAccount.find_by!(user_id: user.id).monthly_payment).to eq(150)
    end

    it 'records paid-until changes with the administrator and keeps them separate from payments' do
      before = Time.utc(2027, 2, 4, 12)
      after = Time.utc(2027, 5, 4, 12)
      user.user_account.update!(paid_until: before)
      payment = ::UserPayment.new(user:, amount: 900, from_date: before - 3.months, to_date: before)
      payment.save!

      2.times do
        as(admin) { json_put update_path(user.id), user_account: { paid_until: after.iso8601 } }
        expect_status(200)
      end

      changes = ::UserPayment.where(user:, expiration_change: true)
      expect(changes.count).to eq(1)
      expect(changes.first).to have_attributes(accounted_by: admin, amount: nil, from_date: before, to_date: after)

      history_path = vpath('/user_payments')
      as(admin) { json_get history_path, user_payment: { user: user.id } }
      expect_status(200)
      expect(json.dig('response', 'user_payments').pluck('id')).to eq([payment.id])

      as(admin) { json_get history_path, user_payment: { user: user.id, include_expiration_changes: 'true' } }
      expect_status(200)
      expect(json.dig('response', 'user_payments').pluck('id')).to eq([changes.first.id, payment.id])
      expect(json.dig('response', 'user_payments', 0)).to include('expiration_change' => true, 'amount' => nil)

      as(user) { json_get history_path }
      expect_status(200)
      expect(json.dig('response', 'user_payments').pluck('id')).to eq([payment.id])

      as(admin) { json_put update_path(user.id), user_account: { paid_until: nil } }
      expect_status(200)
      expect(changes.order(:id).last).to have_attributes(from_date: after, to_date: nil, amount: nil)
    end

    it 'updates paid_until and expiration for admin' do
      paid_until = Time.utc(2026, 1, 25, 12, 0, 0)

      as(admin) { json_put update_path(user.id), user_account: { paid_until: paid_until.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(true)

      acc = ::UserAccount.find_by!(user_id: user.id)
      user_record = ::User.find(user.id)
      expect(acc.paid_until.to_i).to eq(paid_until.to_i)
      expect(user_record.expiration_date.to_i).to eq(paid_until.to_i)
    end
  end
end
