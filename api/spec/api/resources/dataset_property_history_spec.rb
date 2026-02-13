# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'
require 'time'

RSpec.describe 'VpsAdmin::API::Resources::Dataset property history actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
  end

  let(:pool) do
    SpecSeed.pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  let!(:dataset_data) do
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "history-root-#{SecureRandom.hex(4)}"
    )
  end

  let(:dataset) { dataset_data.first }

  let(:used_prop) { dataset.dataset_properties.find_by!(name: 'used') }
  let(:quota_prop) { dataset.dataset_properties.find_by!(name: 'quota') }

  def property_history_path(dataset_id)
    vpath("/datasets/#{dataset_id}/property_history")
  end

  def property_history_item_path(dataset_id, history_id)
    vpath("/datasets/#{dataset_id}/property_history/#{history_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def history_rows
    json.dig('response', 'property_histories') ||
      json.dig('response', 'dataset_property_histories') ||
      []
  end

  def history_obj
    json.dig('response', 'property_history') || json.dig('response', 'dataset_property_history')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_history(property:, value:, created_at:)
    DatasetPropertyHistory.create!(
      dataset_property: property,
      value: value,
      created_at: created_at
    )
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get property_history_path(dataset.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists history in descending order' do
      older = create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))
      newer = create_history(property: used_prop, value: 20, created_at: Time.utc(2024, 1, 2, 12, 0, 0))

      as(user) { json_get property_history_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = history_rows.map { |row| row['id'] }
      expect(ids).to eq([newer.id, older.id])
    end

    it 'filters by name' do
      create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))
      create_history(property: quota_prop, value: 50, created_at: Time.utc(2024, 1, 1, 13, 0, 0))

      as(user) { json_get property_history_path(dataset.id), property_history: { name: 'used' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(history_rows).not_to be_empty
      expect(history_rows).to all(include('name' => 'used'))
    end

    it 'filters by from and to datetime' do
      early = create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 0, 0, 0))
      middle = create_history(property: used_prop, value: 20, created_at: Time.utc(2024, 1, 2, 0, 0, 0))
      late = create_history(property: used_prop, value: 30, created_at: Time.utc(2024, 1, 3, 0, 0, 0))

      as(user) do
        json_get property_history_path(dataset.id), property_history: {
          from: Time.utc(2024, 1, 1, 12, 0, 0).iso8601,
          to: Time.utc(2024, 1, 2, 12, 0, 0).iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = history_rows.map { |row| row['id'] }
      expect(ids).to contain_exactly(middle.id)
      expect(ids).not_to include(early.id, late.id)
    end

    it 'returns 404 for other users' do
      create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))

      as(other_user) { json_get property_history_path(dataset.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      history = create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))
      json_get property_history_item_path(dataset.id, history.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own history row' do
      history = create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))

      as(user) { json_get property_history_item_path(dataset.id, history.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(history_obj['id']).to eq(history.id)
    end

    it 'returns 404 for other users' do
      history = create_history(property: used_prop, value: 10, created_at: Time.utc(2024, 1, 1, 12, 0, 0))

      as(other_user) { json_get property_history_item_path(dataset.id, history.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown id' do
      missing = DatasetPropertyHistory.maximum(:id).to_i + 10

      as(user) { json_get property_history_item_path(dataset.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
