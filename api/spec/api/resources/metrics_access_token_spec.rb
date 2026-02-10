# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::MetricsAccessToken' do
  before do
    header 'Accept', 'application/json'
  end

  let(:users) do
    {
      user: SpecSeed.user,
      other_user: SpecSeed.other_user,
      admin: SpecSeed.admin
    }
  end

  let!(:tokens) do
    {
      user_primary: create_token(user: user, metric_prefix: 'spec_a'),
      user_secondary: create_token(user: user, metric_prefix: 'spec_b'),
      other_user: create_token(user: other_user, metric_prefix: 'spec_c')
    }
  end

  def create_token(user:, metric_prefix:)
    MetricsAccessToken.create_for!(user, metric_prefix)
  end

  def user
    users.fetch(:user)
  end

  def other_user
    users.fetch(:other_user)
  end

  def admin
    users.fetch(:admin)
  end

  def user_primary
    tokens.fetch(:user_primary)
  end

  def user_secondary
    tokens.fetch(:user_secondary)
  end

  def other_user_token
    tokens.fetch(:other_user)
  end

  def index_path
    vpath('/metrics_access_tokens')
  end

  def show_path(id)
    vpath("/metrics_access_tokens/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def token_list
    json.dig('response', 'metrics_access_tokens')
  end

  def token_obj
    json.dig('response', 'metrics_access_token')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def token_user_id(row)
    resource_id(row['user'])
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list their tokens' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = token_list.map { |row| row['id'] }
      expect(ids).to include(user_primary.id, user_secondary.id)
      expect(ids).not_to include(other_user_token.id)

      row = token_list.find { |token| token['id'] == user_primary.id }
      expect(row['metric_prefix']).to eq('spec_a')
      expect(row['access_token']).not_to be_nil
      expect(token_user_id(row)).to eq(user.id)
    end

    it 'ignores user filter for normal users' do
      as(user) { json_get index_path, metrics_access_token: { user: other_user.id } }

      expect_status(200)
      ids = token_list.map { |row| row['id'] }
      expect(ids).to include(user_primary.id, user_secondary.id)
      expect(ids).not_to include(other_user_token.id)
    end

    it 'allows admin to list all tokens' do
      as(admin) { json_get index_path }

      expect_status(200)
      ids = token_list.map { |row| row['id'] }
      expect(ids).to include(user_primary.id, user_secondary.id, other_user_token.id)
    end

    it 'allows admin to filter by user' do
      as(admin) { json_get index_path, metrics_access_token: { user: user.id } }

      expect_status(200)
      ids = token_list.map { |row| row['id'] }
      expect(ids).to include(user_primary.id, user_secondary.id)
      expect(ids).not_to include(other_user_token.id)
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(MetricsAccessToken.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to show their token' do
      as(user) { json_get show_path(user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(token_obj['id']).to eq(user_primary.id)
      expect(token_user_id(token_obj)).to eq(user.id)
      expect(token_obj['metric_prefix']).to eq('spec_a')
      expect(token_obj['access_token']).not_to be_nil
    end

    it 'hides other users tokens from normal users' do
      as(user) { json_get show_path(other_user_token.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any token' do
      as(admin) { json_get show_path(other_user_token.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(token_user_id(token_obj)).to eq(other_user.id)
    end

    it 'returns 404 for unknown token' do
      missing = MetricsAccessToken.maximum(:id).to_i + 100
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, metrics_access_token: { metric_prefix: 'spec_created' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to create a token for themselves' do
      as(user) { json_post index_path, metrics_access_token: { metric_prefix: 'spec_created' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(token_user_id(token_obj)).to eq(user.id)
      expect(token_obj['access_token']).not_to be_nil
      expect(token_obj['metric_prefix']).to eq('spec_created')
    end

    it 'ignores user selection for normal users' do
      as(user) do
        json_post index_path, metrics_access_token: { user: other_user.id, metric_prefix: 'spec_owned' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(token_user_id(token_obj)).to eq(user.id)
      expect(MetricsAccessToken.where(user: other_user, metric_prefix: 'spec_owned')).to be_empty
    end

    it 'allows admin to create a token for other users' do
      as(admin) do
        json_post index_path, metrics_access_token: { user: other_user.id, metric_prefix: 'spec_admin' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(token_user_id(token_obj)).to eq(other_user.id)
      expect(token_obj['metric_prefix']).to eq('spec_admin')
    end

    it 'returns validation errors for invalid metric_prefix' do
      as(user) do
        json_post index_path, metrics_access_token: { metric_prefix: 'bad-prefix!' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('metric_prefix')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to delete their token' do
      as(user) { json_delete show_path(user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MetricsAccessToken.where(id: user_primary.id)).to be_empty
    end

    it 'hides other users tokens from normal users' do
      as(user) { json_delete show_path(other_user_token.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete any token' do
      as(admin) { json_delete show_path(other_user_token.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MetricsAccessToken.where(id: other_user_token.id)).to be_empty
    end
  end
end
