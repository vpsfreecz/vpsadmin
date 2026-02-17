# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User', requires_plugins: :payments do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    seed_payments_sysconfig!(
      default_currency: 'CZK',
      conversion_rates: {},
      payment_instructions: 'Hello <%= user.login %>, monthly=<%= monthly_payment %>'
    )
    SpecSeed.user.user_account.update!(monthly_payment: 123)
  end

  def instructions_path(id)
    vpath("/users/#{id}/get_payment_instructions")
  end

  def current_path
    vpath('/users/current')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def instructions
    json.dig('response', 'instructions') || json['response']
  end

  def user_obj
    json.dig('response', 'user') || json['response']
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

  describe 'GetPaymentInstructions' do
    it 'rejects unauthenticated access' do
      json_get instructions_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to fetch instructions for themselves' do
      as(user) { json_get instructions_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(instructions.to_s).to include('user')
      expect(instructions.to_s).to include('123')
    end

    it 'rejects users from fetching instructions for others' do
      as(user) { json_get instructions_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg.to_s).to include('access denied')
    end

    it 'allows admin to fetch instructions for other users' do
      as(admin) { json_get instructions_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'User output override' do
    it 'includes monthly_payment and paid_until in current user output' do
      as(user) { json_get current_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_obj).to include('monthly_payment', 'paid_until')
    end
  end
end
