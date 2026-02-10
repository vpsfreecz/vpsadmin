# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User' do
  before do
    header 'Accept', 'application/json'
  end

  def index_path
    vpath('/users')
  end

  def show_path(id)
    vpath("/users/#{id}")
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

  def users
    json.dig('response', 'users')
  end

  def user_obj
    json.dig('response', 'user') || json['response']
  end

  def extract_login(obj)
    obj['login'] || obj['username'] || obj['name']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes user endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('user#current', 'user#index', 'user#show')
    end
  end

  describe 'Current' do
    it 'rejects unauthenticated access' do
      json_get current_path

      expect(last_response.status).to be_in([401, 403])
      expect(json['status']).to be(false)
    end

    it 'returns current user for normal user' do
      as(SpecSeed.user) { json_get current_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(extract_login(user_obj)).to eq('user')
      expect(user_obj['id']).to eq(SpecSeed.user.id) if user_obj.has_key?('id')
    end

    it 'returns current user for admin' do
      as(SpecSeed.admin) { json_get current_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(extract_login(user_obj)).to eq('admin')
    end

    it 'includes expected fields for normal user' do
      as(SpecSeed.user) { json_get current_path }

      expect_status(200)
      expect(user_obj).to include('id', 'login', 'email', 'level', 'enable_basic_auth')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(SpecSeed.user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show themselves' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(extract_login(user_obj)).to eq('user')
      expect(user_obj['id']).to eq(SpecSeed.user.id)
    end

    it 'rejects users from showing another user' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'rejects support from showing another user' do
      as(SpecSeed.support) { json_get show_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any user' do
      as(SpecSeed.admin) { json_get show_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(extract_login(user_obj)).to eq(SpecSeed.other_user.login)
    end

    it 'returns 404 for unknown user' do
      missing = User.maximum(:id).to_i + 10
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns only the current user for normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(users.length).to eq(1)
      expect(extract_login(users.first)).to eq('user')
    end

    it 'returns only the current user for support' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(users.length).to eq(1)
      expect(extract_login(users.first)).to eq('support')
    end

    it 'allows admin to list users' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      logins = users.map { |row| extract_login(row) }
      expect(logins).to include('admin', 'support', 'user', SpecSeed.other_user.login)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(User.existing.count)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, user: { limit: 1 } }

      expect_status(200)
      expect(users.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = User.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, user: { from_id: boundary } }

      expect_status(200)
      ids = users.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Output' do
    let(:expected_fields) do
      %w[id login full_name email level enable_basic_auth enable_multi_factor_auth created_at]
    end

    it 'includes expected fields for normal users' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.user.id) }

      expect_status(200)
      expected_fields.each do |field|
        expect(user_obj).to include(field)
      end
    end

    it 'includes expected fields for admins' do
      as(SpecSeed.admin) { json_get show_path(SpecSeed.admin.id) }

      expect_status(200)
      expected_fields.each do |field|
        expect(user_obj).to include(field)
      end
    end

    it 'returns role-specific dokuwiki_groups' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.user.id) }

      expect_status(200)
      expect(user_obj['dokuwiki_groups']).to eq('user')

      as(SpecSeed.admin) { json_get show_path(SpecSeed.admin.id) }

      expect_status(200)
      expect(user_obj['dokuwiki_groups']).to eq('admin,user')
    end
  end
end
