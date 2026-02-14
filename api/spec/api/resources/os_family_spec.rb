# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::OsFamily' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user

    OsFamily.create!(label: 'AAA Family', description: 'a')
    OsFamily.create!(label: 'ZZZ Family', description: 'z')
  end

  def index_path
    vpath('/os_families')
  end

  def show_path(id)
    vpath("/os_families/#{id}")
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

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def os_families
    json.dig('response', 'os_families') || []
  end

  def os_family
    json.dig('response', 'os_family') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to list os families' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_families).to be_an(Array)

      labels = os_families.map { |item| item['label'] }
      expect(labels).to include('AAA Family', 'Spec OS', 'ZZZ Family')
    end

    it 'allows admins to list os families' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'orders families by label' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      labels = os_families.map { |item| item['label'] }
      expect(labels).to eq(labels.sort)
    end

    it 'supports limit pagination' do
      as(SpecSeed.user) { json_get index_path, os_family: { limit: 1 } }

      expect_status(200)
      expect(os_families.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = OsFamily.find_by!(label: 'AAA Family').id
      as(SpecSeed.user) { json_get index_path, os_family: { from_id: boundary } }

      expect_status(200)
      ids = os_families.map { |item| item['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.user) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(OsFamily.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(SpecSeed.os_family.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows an os family for users' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.os_family.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_family['id']).to eq(SpecSeed.os_family.id)
      expect(os_family['label']).to eq('Spec OS')
      expect(os_family).to include('description')
    end

    it 'allows admins to show an os family' do
      as(SpecSeed.admin) { json_get show_path(SpecSeed.os_family.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown family' do
      missing = OsFamily.maximum(:id).to_i + 100
      as(SpecSeed.user) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, os_family: { label: 'X' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, os_family: { label: 'X' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create an os family' do
      as(SpecSeed.admin) do
        json_post index_path, os_family: { label: 'Spec Created Family', description: 'desc' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      record = OsFamily.find_by!(label: 'Spec Created Family')
      expect(record.description).to eq('desc')
      expect(os_family['label']).to eq('Spec Created Family')
      expect(os_family['description']).to eq('desc')
    end

    it 'returns validation errors for missing label' do
      as(SpecSeed.admin) { json_post index_path, os_family: { description: 'x' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('label')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(SpecSeed.os_family.id), os_family: { label: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(SpecSeed.os_family.id), os_family: { label: 'Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update an os family' do
      to_update = OsFamily.create!(label: 'Update Me')

      as(SpecSeed.admin) do
        json_put show_path(to_update.id), os_family: { label: 'Updated', description: 'new' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(to_update.reload.label).to eq('Updated')
      expect(to_update.description).to eq('new')
      expect(os_family['label']).to eq('Updated')
      expect(os_family['description']).to eq('new')
    end

    it 'returns validation errors for blank label' do
      to_update = OsFamily.create!(label: 'Keep Me')

      as(SpecSeed.admin) { json_put show_path(to_update.id), os_family: { label: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('label')
      expect(to_update.reload.label).to eq('Keep Me')
    end

    it 'returns 404 for unknown family' do
      missing = OsFamily.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_put show_path(missing), os_family: { label: 'Updated' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(SpecSeed.os_family.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(SpecSeed.os_family.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete unused os families' do
      to_delete = OsFamily.create!(label: 'Delete Me')

      as(SpecSeed.admin) { json_delete show_path(to_delete.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(OsFamily.where(id: to_delete.id)).to be_empty
    end

    it 'rejects delete when os family is in use' do
      as(SpecSeed.admin) { json_delete show_path(SpecSeed.os_family.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('in use')
      expect(OsFamily.where(id: SpecSeed.os_family.id)).not_to be_empty
    end
  end
end
