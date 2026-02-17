# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserOutage', requires_plugins: :outage_reports do
  include OutageReportsSpecHelpers

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
  end

  def index_path
    vpath('/user_outages')
  end

  def show_path(id)
    vpath("/user_outages/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def user_outages
    json.dig('response', 'user_outages') || []
  end

  def user_outage_obj
    json.dig('response', 'user_outage') || json['response']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def build_outage(attrs = {})
    defaults = {
      begins_at: Time.utc(2026, 1, 1, 12, 0, 0),
      duration: 60,
      outage_type: :outage,
      impact_type: :network,
      state: :announced,
      auto_resolve: true
    }
    create_outage_with_translation!(defaults.merge(attrs))
  end

  def admin
    SpecSeed.admin
  end

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  describe 'API description' do
    it 'includes user_outage endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('user_outage#index', 'user_outage#show')
    end
  end

  describe 'Index' do
    let!(:outage) { build_outage }
    let!(:user_outage_row) do
      ::OutageUser.create!(outage: outage, user: user, vps_count: 1, export_count: 0)
    end
    let!(:other_outage_row) do
      ::OutageUser.create!(outage: outage, user: other_user, vps_count: 2, export_count: 1)
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only own rows for normal users' do
      as(user) { json_get index_path }

      expect_status(200)
      ids = user_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_outage_row.id)
    end

    it 'shows all rows for admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      ids = user_outages.map { |row| row['id'] }
      expect(ids).to include(user_outage_row.id, other_outage_row.id)
    end

    it 'filters by outage' do
      other = build_outage(begins_at: Time.utc(2026, 1, 3, 12, 0, 0))
      filtered = ::OutageUser.create!(outage: other, user: user, vps_count: 0, export_count: 0)

      as(admin) { json_get index_path, user_outage: { outage: other.id } }

      expect_status(200)
      ids = user_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(filtered.id)
    end
  end

  describe 'Show' do
    let!(:outage) { build_outage }
    let!(:user_outage_row) do
      ::OutageUser.create!(outage: outage, user: user, vps_count: 1, export_count: 0)
    end
    let!(:other_outage_row) do
      ::OutageUser.create!(outage: outage, user: other_user, vps_count: 2, export_count: 1)
    end

    it 'rejects unauthenticated access' do
      json_get show_path(user_outage_row.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to view their own rows' do
      as(user) { json_get show_path(user_outage_row.id) }

      expect_status(200)
      expect(user_outage_obj['id']).to eq(user_outage_row.id)
    end

    it 'hides other users rows from normal users' do
      as(user) { json_get show_path(other_outage_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view any row' do
      as(admin) { json_get show_path(other_outage_row.id) }

      expect_status(200)
      expect(user_outage_obj['id']).to eq(other_outage_row.id)
    end
  end
end
