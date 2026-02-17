# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::VpsOutage', requires_plugins: :outage_reports do
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
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/vps_outages')
  end

  def show_path(id)
    vpath("/vps_outages/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def vps_outages
    json.dig('response', 'vps_outages') || []
  end

  def vps_outage_obj
    json.dig('response', 'vps_outage') || json['response']
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
    it 'includes vps_outage endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('vps_outage#index', 'vps_outage#show')
    end
  end

  describe 'Index' do
    let!(:outage) { build_outage }
    let!(:user_vps) { create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-user-vps') }
    let!(:other_vps) { create_vps!(user: other_user, node: SpecSeed.other_node, hostname: 'spec-other-vps') }
    let!(:user_row) do
      ::OutageVps.create!(
        outage: outage,
        vps: user_vps,
        user: user,
        environment: user_vps.node.location.environment,
        location: user_vps.node.location,
        node: user_vps.node,
        direct: true
      )
    end
    let!(:other_row) do
      ::OutageVps.create!(
        outage: outage,
        vps: other_vps,
        user: other_user,
        environment: other_vps.node.location.environment,
        location: other_vps.node.location,
        node: other_vps.node,
        direct: false
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
      ids = vps_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_row.id)
    end

    it 'shows all rows for admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      ids = vps_outages.map { |row| row['id'] }
      expect(ids).to include(user_row.id, other_row.id)
    end

    it 'filters by direct for admins' do
      as(admin) { json_get index_path, vps_outage: { direct: true } }

      expect_status(200)
      ids = vps_outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_row.id)
    end
  end

  describe 'Show' do
    let!(:outage) { build_outage }
    let!(:user_vps) { create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-user-vps') }
    let!(:other_vps) { create_vps!(user: other_user, node: SpecSeed.other_node, hostname: 'spec-other-vps') }
    let!(:user_row) do
      ::OutageVps.create!(
        outage: outage,
        vps: user_vps,
        user: user,
        environment: user_vps.node.location.environment,
        location: user_vps.node.location,
        node: user_vps.node,
        direct: true
      )
    end
    let!(:other_row) do
      ::OutageVps.create!(
        outage: outage,
        vps: other_vps,
        user: other_user,
        environment: other_vps.node.location.environment,
        location: other_vps.node.location,
        node: other_vps.node,
        direct: false
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
      expect(vps_outage_obj['id']).to eq(user_row.id)
    end

    it 'hides other users rows from normal users' do
      as(user) { json_get show_path(other_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view any row' do
      as(admin) { json_get show_path(other_row.id) }

      expect_status(200)
      expect(vps_outage_obj['id']).to eq(other_row.id)
    end
  end
end
