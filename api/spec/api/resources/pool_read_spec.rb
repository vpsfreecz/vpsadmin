# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Pool' do
  let(:pool) { Pool.find(SpecSeed.pool.id) }
  let(:other_pool) { Pool.find(SpecSeed.other_pool.id) }
  let(:checked_at) { Time.utc(2026, 4, 2, 10, 0, 0) }

  before do
    header 'Accept', 'application/json'
    pool
    other_pool

    pool.update!(
      total_space: 20_480,
      used_space: 8_192,
      available_space: 12_288,
      checked_at:
    )
    other_pool.update!(
      total_space: 10_240,
      used_space: 2_048,
      available_space: 8_192,
      checked_at:
    )
  end

  def index_path
    vpath('/pools')
  end

  def show_path(id)
    vpath("/pools/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def pools
    json.dig('response', 'pools')
  end

  def pool_obj
    json.dig('response', 'pool')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
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

    it 'allows users to list pools with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(pools).to be_an(Array)

      ids = pools.map { |row| row['id'] }
      expect(ids).to include(pool.id, other_pool.id)

      row = pools.find { |item| item['id'] == pool.id }
      expect(row).to include(
        'id',
        'node',
        'name',
        'role',
        'state',
        'scan',
        'scan_percent',
        'checked_at'
      )
      expect(row['name']).to eq(pool.name)
      expect(resource_id(row['node'])).to eq(pool.node_id)
      expect(row['role']).to eq(pool.role)
      expect(row['checked_at']).to eq(checked_at.iso8601)
      expect(row).not_to have_key('total_space')
      expect(row).not_to have_key('used_space')
      expect(row).not_to have_key('available_space')
      expect(row).not_to have_key('label')
      expect(row).not_to have_key('filesystem')
    end

    it 'allows support to list pools with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      row = pools.find { |item| item['id'] == pool.id }
      expect(row['checked_at']).to eq(checked_at.iso8601)
      expect(row).not_to have_key('total_space')
      expect(row).not_to have_key('used_space')
      expect(row).not_to have_key('available_space')
      expect(row).not_to have_key('label')
      expect(row).not_to have_key('filesystem')
    end

    it 'allows admins to list pools with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      row = pools.find { |item| item['id'] == pool.id }
      expect(row['label']).to eq(pool.label)
      expect(row['filesystem']).to eq(pool.filesystem)
      expect(row['refquota_check']).to eq(pool.refquota_check)
      expect(row['max_datasets']).to eq(pool.max_datasets)
      expect(row['total_space']).to eq(20_480)
      expect(row['used_space']).to eq(8_192)
      expect(row['available_space']).to eq(12_288)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, pool: { limit: 1 } }

      expect_status(200)
      expect(pools.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Pool.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, pool: { from_id: boundary } }

      expect_status(200)
      ids = pools.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Pool.count)
    end

    it 'filters by node' do
      as(SpecSeed.admin) { json_get index_path, pool: { node: pool.node_id } }

      expect_status(200)
      ids = pools.map { |row| row['id'] }
      expect(ids).to include(pool.id)
      expect(ids).not_to include(other_pool.id)
    end

    it 'filters by label' do
      as(SpecSeed.admin) { json_get index_path, pool: { label: pool.label } }

      expect_status(200)
      ids = pools.map { |row| row['id'] }
      expect(ids).to include(pool.id)
      expect(ids).not_to include(other_pool.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(pool.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show pools with limited output' do
      as(SpecSeed.user) { json_get show_path(pool.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(pool_obj['id']).to eq(pool.id)
      expect(pool_obj['name']).to eq(pool.name)
      expect(resource_id(pool_obj['node'])).to eq(pool.node_id)
      expect(pool_obj['role']).to eq(pool.role)
      expect(pool_obj['checked_at']).to eq(checked_at.iso8601)
      expect(pool_obj).not_to have_key('total_space')
      expect(pool_obj).not_to have_key('used_space')
      expect(pool_obj).not_to have_key('available_space')
      expect(pool_obj).not_to have_key('label')
      expect(pool_obj).not_to have_key('filesystem')
    end

    it 'allows support to show pools with limited output' do
      as(SpecSeed.support) { json_get show_path(pool.id) }

      expect_status(200)
      expect(pool_obj['checked_at']).to eq(checked_at.iso8601)
      expect(pool_obj).not_to have_key('total_space')
      expect(pool_obj).not_to have_key('used_space')
      expect(pool_obj).not_to have_key('available_space')
      expect(pool_obj).not_to have_key('label')
      expect(pool_obj).not_to have_key('filesystem')
    end

    it 'allows admins to show pools with full output' do
      as(SpecSeed.admin) { json_get show_path(pool.id) }

      expect_status(200)
      expect(pool_obj['id']).to eq(pool.id)
      expect(pool_obj['label']).to eq(pool.label)
      expect(pool_obj['filesystem']).to eq(pool.filesystem)
      expect(pool_obj['refquota_check']).to eq(pool.refquota_check)
      expect(pool_obj['max_datasets']).to eq(pool.max_datasets)
      expect(pool_obj['total_space']).to eq(20_480)
      expect(pool_obj['used_space']).to eq(8_192)
      expect(pool_obj['available_space']).to eq(12_288)
    end

    it 'returns 404 for unknown pool' do
      missing = Pool.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
