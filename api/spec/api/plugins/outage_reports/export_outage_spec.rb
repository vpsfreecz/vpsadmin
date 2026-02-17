# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::ExportOutage', requires_plugins: :outage_reports do
  include OutageReportsSpecHelpers

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.location
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
  end

  def index_path
    vpath('/export_outages')
  end

  def show_path(id)
    vpath("/export_outages/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def export_outages
    json.dig('response', 'export_outages') || []
  end

  def export_outage_obj
    json.dig('response', 'export_outage') || json['response']
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
    it 'includes export_outage endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('export_outage#index', 'export_outage#show')
    end
  end

  describe 'Index' do
    let!(:outage) { build_outage }
    let!(:user_export) { create_export!(user: user, pool: SpecSeed.pool) }
    let!(:other_export) { create_export!(user: other_user, pool: SpecSeed.other_pool) }
    let!(:user_row) do
      pool = user_export.dataset_in_pool.pool
      ::OutageExport.create!(
        outage: outage,
        export: user_export,
        user: user,
        environment: pool.node.location.environment,
        location: pool.node.location,
        node: pool.node
      )
    end
    let!(:other_row) do
      pool = other_export.dataset_in_pool.pool
      ::OutageExport.create!(
        outage: outage,
        export: other_export,
        user: other_user,
        environment: pool.node.location.environment,
        location: pool.node.location,
        node: pool.node
      )
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only own rows for normal users' do
      as(user) { json_get index_path }

      expect_status(200)
      ids = export_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_row.id)
    end

    it 'shows all rows for admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      ids = export_outages.map { |row| row['id'] }
      expect(ids).to include(user_row.id, other_row.id)
    end

    it 'filters by outage' do
      other = build_outage(begins_at: Time.utc(2026, 1, 3, 12, 0, 0))
      export = create_export!(user: user, pool: SpecSeed.pool)
      pool = export.dataset_in_pool.pool
      filtered = ::OutageExport.create!(
        outage: other,
        export: export,
        user: user,
        environment: pool.node.location.environment,
        location: pool.node.location,
        node: pool.node
      )

      as(admin) { json_get index_path, export_outage: { outage: other.id } }

      expect_status(200)
      ids = export_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(filtered.id)
    end
  end

  describe 'Show' do
    let!(:outage) { build_outage }
    let!(:user_export) { create_export!(user: user, pool: SpecSeed.pool) }
    let!(:other_export) { create_export!(user: other_user, pool: SpecSeed.other_pool) }
    let!(:user_row) do
      pool = user_export.dataset_in_pool.pool
      ::OutageExport.create!(
        outage: outage,
        export: user_export,
        user: user,
        environment: pool.node.location.environment,
        location: pool.node.location,
        node: pool.node
      )
    end
    let!(:other_row) do
      pool = other_export.dataset_in_pool.pool
      ::OutageExport.create!(
        outage: outage,
        export: other_export,
        user: other_user,
        environment: pool.node.location.environment,
        location: pool.node.location,
        node: pool.node
      )
    end

    it 'rejects unauthenticated access' do
      json_get show_path(user_row.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to view their own rows' do
      as(user) { json_get show_path(user_row.id) }

      expect_status(200)
      expect(export_outage_obj['id']).to eq(user_row.id)
    end

    it 'hides other users rows from normal users' do
      as(user) { json_get show_path(other_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view any row' do
      as(admin) { json_get show_path(other_row.id) }

      expect_status(200)
      expect(export_outage_obj['id']).to eq(other_row.id)
    end
  end
end
