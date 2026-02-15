# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserNamespace' do
  before do
    header 'Accept', 'application/json'
  end

  let!(:user_ns_a) do
    UserNamespace.create!(
      user: SpecSeed.user,
      block_count: 1,
      offset: 10_000,
      size: 32
    )
  end
  let!(:user_ns_b) do
    UserNamespace.create!(
      user: SpecSeed.user,
      block_count: 2,
      offset: 20_000,
      size: 64
    )
  end
  let!(:other_ns) do
    UserNamespace.create!(
      user: SpecSeed.other_user,
      block_count: 3,
      offset: 30_000,
      size: 64
    )
  end
  let!(:support_ns) do
    UserNamespace.create!(
      user: SpecSeed.support,
      block_count: 4,
      offset: 40_000,
      size: 128
    )
  end

  def index_path
    vpath('/user_namespaces')
  end

  def show_path(id)
    vpath("/user_namespaces/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def ns_list
    json.dig('response', 'user_namespaces')
  end

  def ns_obj
    json.dig('response', 'user_namespace')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def ns_user_id(row)
    resource_id(row['user'])
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes user_namespace endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('user_namespace#index', 'user_namespace#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list only their namespaces' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_a.id, user_ns_b.id)
      expect(ids).not_to include(other_ns.id, support_ns.id)
    end

    it 'filters output for normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      row = ns_list.find { |ns| ns['id'] == user_ns_a.id }
      expect(row).to include('id', 'size')
      expect(row).not_to include('user', 'offset', 'block_count')
    end

    it 'ignores block_count filter for normal users' do
      as(SpecSeed.user) { json_get index_path, user_namespace: { block_count: 999 } }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_a.id, user_ns_b.id)
    end

    it 'allows normal users to filter by size' do
      as(SpecSeed.user) { json_get index_path, user_namespace: { size: 32 } }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_a.id)
      expect(ids).not_to include(user_ns_b.id)
      expect(ns_list).to all(include('size' => 32))
    end

    it 'allows normal users to filter by size 64' do
      as(SpecSeed.user) { json_get index_path, user_namespace: { size: 64 } }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_b.id)
      expect(ids).not_to include(user_ns_a.id)
      expect(ns_list).to all(include('size' => 64))
    end

    it 'allows support users to list only their namespaces with filtered output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(support_ns.id)
      expect(ids).not_to include(user_ns_a.id, other_ns.id)
      row = ns_list.find { |ns| ns['id'] == support_ns.id }
      expect(row).to include('id', 'size')
      expect(row).not_to include('user', 'offset', 'block_count')
    end

    it 'allows admin to list all namespaces with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_a.id, user_ns_b.id, other_ns.id, support_ns.id)
      row = ns_list.find { |ns| ns['id'] == other_ns.id }
      expect(row).to include('id', 'user', 'offset', 'block_count', 'size')
    end

    it 'allows admin to filter by user' do
      as(SpecSeed.admin) { json_get index_path, user_namespace: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to include(user_ns_a.id, user_ns_b.id)
      expect(ns_list).to all(satisfy { |row| ns_user_id(row) == SpecSeed.user.id })
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, user_namespace: { limit: 1 } }

      expect_status(200)
      expect(ns_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = UserNamespace.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, user_namespace: { from_id: boundary } }

      expect_status(200)
      ids = ns_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(UserNamespace.count)
    end

    it 'rejects invalid size filter' do
      pending('HaveAPI should validate integer input types')

      as(SpecSeed.admin) { json_get index_path, user_namespace: { size: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors'] || {}
      expect(errors).to include('size')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_ns_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to show their namespace' do
      as(SpecSeed.user) { json_get show_path(user_ns_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ns_obj).to include('id', 'size')
      expect(ns_obj).not_to include('user', 'offset', 'block_count')
    end

    it 'hides other users namespaces from normal users' do
      as(SpecSeed.user) { json_get show_path(other_ns.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any namespace with full output' do
      as(SpecSeed.admin) { json_get show_path(other_ns.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ns_obj).to include('id', 'user', 'offset', 'block_count', 'size')
    end

    it 'returns 404 for unknown namespace' do
      missing = UserNamespace.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
