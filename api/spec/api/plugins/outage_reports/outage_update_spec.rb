# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::OutageUpdate', requires_plugins: :outage_reports do
  include OutageReportsSpecHelpers

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
  end

  def index_path
    vpath('/outage_updates')
  end

  def show_path(id)
    vpath("/outage_updates/#{id}")
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

  def updates
    json.dig('response', 'outage_updates') || json.dig('response', 'updates') || []
  end

  def update_obj
    json.dig('response', 'outage_update') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
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
      state: :staged,
      auto_resolve: true
    }
    create_outage_with_translation!(defaults.merge(attrs))
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }

  describe 'API description' do
    it 'includes outage_update endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('outage_update#index', 'outage_update#show', 'outage_update#create')
    end
  end

  describe 'Index' do
    let!(:outage) { build_outage(state: :staged) }
    let!(:staged_update) do
      ::OutageUpdate.create!(
        outage: outage,
        reported_by: admin,
        state: :staged,
        created_at: Time.utc(2026, 1, 1, 10, 0, 0)
      )
    end
    let!(:announced_update) do
      ::OutageUpdate.create!(
        outage: outage,
        reported_by: admin,
        state: :announced,
        created_at: Time.utc(2026, 1, 2, 10, 0, 0)
      )
    end

    it 'allows unauthenticated access' do
      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'hides staged updates from unauthenticated users' do
      json_get index_path

      expect_status(200)
      ids = updates.map { |row| row['id'] }
      expect(ids).to include(announced_update.id)
      expect(ids).not_to include(staged_update.id)
    end

    it 'shows staged updates to admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      ids = updates.map { |row| row['id'] }
      expect(ids).to include(announced_update.id, staged_update.id)
    end

    it 'filters by outage' do
      other_outage = build_outage(state: :staged, begins_at: Time.utc(2026, 1, 5, 12, 0, 0))
      other_update = ::OutageUpdate.create!(
        outage: other_outage,
        reported_by: admin,
        state: :announced,
        created_at: Time.utc(2026, 1, 3, 10, 0, 0)
      )

      as(admin) { json_get index_path, outage_update: { outage: other_outage.id } }

      expect_status(200)
      ids = updates.map { |row| row['id'] }
      expect(ids).to contain_exactly(other_update.id)
    end

    it 'filters by since' do
      cutoff = Time.utc(2026, 1, 1, 18, 0, 0)

      as(admin) { json_get index_path, outage_update: { since: cutoff.iso8601 } }

      expect_status(200)
      ids = updates.map { |row| row['id'] }
      expect(ids).to contain_exactly(announced_update.id)
    end
  end

  describe 'Show' do
    let!(:outage) { build_outage(state: :staged) }
    let!(:staged_update) do
      ::OutageUpdate.create!(
        outage: outage,
        reported_by: admin,
        state: :staged,
        created_at: Time.utc(2026, 1, 1, 10, 0, 0)
      )
    end
    let!(:announced_update) do
      ::OutageUpdate.create!(
        outage: outage,
        reported_by: admin,
        state: :announced,
        created_at: Time.utc(2026, 1, 2, 10, 0, 0)
      )
    end

    it 'allows unauthenticated access to announced updates' do
      json_get show_path(announced_update.id)

      expect_status(200)
      expect(update_obj['id']).to eq(announced_update.id)
    end

    it 'hides staged updates from unauthenticated users' do
      json_get show_path(staged_update.id)

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view staged updates' do
      as(admin) { json_get show_path(staged_update.id) }

      expect_status(200)
      expect(update_obj['id']).to eq(staged_update.id)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, outage_update: { outage: 123, state: 'staged', send_mail: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users' do
      as(user) { json_post index_path, outage_update: { outage: 123, state: 'staged', send_mail: false } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'rejects same-state updates' do
      outage = build_outage(state: :staged)

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          state: 'staged',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      state_errors = errors['state']
      if state_errors
        expect(state_errors.join(' ')).to include('already staged')
      else
        expect(msg).to include('already staged')
      end
    end

    it 'rejects announcing non-staged outages' do
      outage = build_outage(state: :resolved)

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          state: 'announced',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Only staged outages can be announced')
    end

    it 'rejects announcing without handlers' do
      outage = build_outage(state: :staged)
      ::OutageEntity.create!(outage: outage, name: 'CustomEntity', row_id: 123)

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          state: 'announced',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Add at least one outage handler')
    end

    it 'rejects announcing without entities' do
      outage = build_outage(state: :staged)
      ::OutageHandler.create!(outage: outage, user: admin, note: 'Spec handler')

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          state: 'announced',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Add at least one entity impaired by the outage')
    end

    it 'announces staged outages with handlers and entities' do
      outage = build_outage(state: :staged)
      ::OutageHandler.create!(outage: outage, user: admin, note: 'Spec handler')
      ::OutageEntity.create!(outage: outage, name: 'Node', row_id: SpecSeed.node.id)

      before_count = ::OutageUpdate.where(outage: outage).count

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          state: 'announced',
          send_mail: false,
          en_summary: 'Announced outage',
          en_description: 'Details'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      outage.reload
      expect(outage.state).to eq('announced')
      expect(::OutageUpdate.where(outage: outage).count).to be > before_count
    end

    it 'creates a non-state update and updates outage attributes' do
      outage = build_outage(state: :announced, duration: 60)

      before_count = ::OutageUpdate.where(outage: outage).count

      as(admin) do
        json_post index_path, outage_update: {
          outage: outage.id,
          duration: 120,
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      outage.reload
      expect(outage.duration).to eq(120)
      expect(::OutageUpdate.where(outage: outage).count).to be > before_count
    end
  end
end
