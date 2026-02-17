# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Outage', requires_plugins: :outage_reports do
  include OutageReportsSpecHelpers

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.support
    SpecSeed.location
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/outages')
  end

  def show_path(id)
    vpath("/outages/#{id}")
  end

  def rebuild_path(id)
    vpath("/outages/#{id}/rebuild_affected_vps")
  end

  def entity_index_path(outage_id)
    vpath("/outages/#{outage_id}/entities")
  end

  def entity_show_path(outage_id, entity_id)
    vpath("/outages/#{outage_id}/entities/#{entity_id}")
  end

  def handler_index_path(outage_id)
    vpath("/outages/#{outage_id}/handlers")
  end

  def handler_show_path(outage_id, handler_id)
    vpath("/outages/#{outage_id}/handlers/#{handler_id}")
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

  def outages
    json.dig('response', 'outages') || []
  end

  def outage_obj
    json.dig('response', 'outage') || json['response']
  end

  def entities
    json.dig('response', 'entities') || json.dig('response', 'outage_entities') || []
  end

  def entity_obj
    json.dig('response', 'entity') || json.dig('response', 'outage_entity') || json['response']
  end

  def handlers
    json.dig('response', 'handlers') || json.dig('response', 'outage_handlers') || []
  end

  def handler_obj
    json.dig('response', 'handler') || json.dig('response', 'outage_handler') || json['response']
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
  let(:other_user) { SpecSeed.other_user }

  describe 'API description' do
    it 'includes outage endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'outage#index', 'outage#show', 'outage#create', 'outage#update', 'outage#rebuild_affected_vps',
        'outage.entity#index', 'outage.entity#show', 'outage.entity#create', 'outage.entity#delete',
        'outage.handler#index', 'outage.handler#show', 'outage.handler#create', 'outage.handler#update',
        'outage.handler#delete'
      )
    end
  end

  describe 'Index' do
    it 'allows unauthenticated access and hides staged outages' do
      staged = build_outage(state: :staged, begins_at: Time.utc(2026, 1, 1, 12, 0, 0))
      announced = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 2, 12, 0, 0))

      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)
      ids = outages.map { |row| row['id'] }
      expect(ids).not_to include(staged.id)
      expect(ids).to include(announced.id)
    end

    it 'shows staged outages to admins' do
      staged = build_outage(state: :staged, begins_at: Time.utc(2026, 1, 1, 12, 0, 0))
      announced = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 2, 12, 0, 0))

      as(admin) { json_get index_path }

      expect_status(200)
      ids = outages.map { |row| row['id'] }
      expect(ids).to include(staged.id, announced.id)
    end

    it 'filters by state' do
      build_outage(state: :staged, begins_at: Time.utc(2026, 1, 1, 12, 0, 0))
      announced = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 2, 12, 0, 0))

      as(admin) { json_get index_path, outage: { state: 'announced' } }

      expect_status(200)
      ids = outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(announced.id)
    end

    it 'filters by entity name and id' do
      target = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 3, 12, 0, 0))
      build_outage(state: :announced, begins_at: Time.utc(2026, 1, 4, 12, 0, 0))

      ::OutageEntity.create!(outage: target, name: 'Node', row_id: SpecSeed.node.id)

      json_get index_path, outage: { entity_name: 'Node', entity_id: SpecSeed.node.id }

      expect_status(200)
      ids = outages.map { |row| row['id'] }
      expect(ids).to contain_exactly(target.id)
    end

    it 'orders results by begins_at for oldest' do
      older = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 1, 8, 0, 0))
      newer = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 1, 10, 0, 0))

      json_get index_path, outage: { state: 'announced', order: 'oldest' }

      expect_status(200)
      ids = outages.map { |row| row['id'] }
      expect(ids).to start_with(older.id, newer.id)
    end

    it 'returns announced and recently updated resolved outages for recent_since' do
      announced = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 4, 12, 0, 0))
      resolved_old = build_outage(state: :resolved, begins_at: Time.utc(2026, 1, 2, 12, 0, 0))
      resolved_recent = build_outage(state: :resolved, begins_at: Time.utc(2026, 1, 3, 12, 0, 0))

      cutoff = Time.utc(2026, 1, 5, 12, 0, 0)
      resolved_old.update_column(:updated_at, cutoff - 2.days)
      resolved_recent.update_column(:updated_at, cutoff + 1.minute)

      json_get index_path, outage: { recent_since: cutoff.iso8601 }

      expect_status(200)
      ids = outages.map { |row| row['id'] }
      expect(ids).to include(announced.id, resolved_recent.id)
      expect(ids).not_to include(resolved_old.id)
    end
  end

  describe 'Show' do
    it 'allows unauthenticated access to non-staged outages' do
      announced = build_outage(state: :announced)

      json_get show_path(announced.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(outage_obj['id']).to eq(announced.id)
    end

    it 'hides staged outages from unauthenticated users' do
      staged = build_outage(state: :staged)

      json_get show_path(staged.id)

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view staged outages' do
      staged = build_outage(state: :staged)

      as(admin) { json_get show_path(staged.id) }

      expect_status(200)
      expect(outage_obj['id']).to eq(staged.id)
    end

    it 'returns 404 for missing outage' do
      json_get show_path(999_999)

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        outage: {
          begins_at: Time.utc(2026, 1, 10, 10, 0, 0).iso8601,
          duration: 60,
          type: 'outage',
          impact: 'network',
          auto_resolve: true,
          en_summary: 'Spec outage',
          en_description: 'Spec description'
        }
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users' do
      as(user) { json_post index_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create outages with translations' do
      as(admin) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(outage_obj['state']).to eq('staged')
      expect(outage_obj['type']).to eq('outage')
      expect(outage_obj['impact']).to eq('network')
      expect(outage_obj['en_summary']).to eq('Spec outage')
      expect(outage_obj['en_description']).to eq('Spec description')

      created = ::Outage.order(:id).last
      expect(created.begins_at.iso8601).to eq(payload[:outage][:begins_at])
      expect(created.duration).to eq(60)

      lang = ::Language.find_by(code: 'en')
      translation = ::OutageTranslation.find_by(outage: created, language: lang)
      expect(translation).not_to be_nil
      expect(translation.summary).to eq('Spec outage')
    end

    it 'requires en_summary' do
      bad_payload = payload.deep_dup
      bad_payload[:outage].delete(:en_summary)

      as(admin) { json_post index_path, bad_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      summary_errors = errors['en_summary']
      if summary_errors
        expect(summary_errors.join(' ')).to include('required')
      else
        expect(msg).to include('input parameters not valid')
      end
    end

    it 'requires begins_at' do
      bad_payload = payload.deep_dup
      bad_payload[:outage].delete(:begins_at)

      as(admin) { json_post index_path, bad_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      begins_at_errors = errors['begins_at']
      if begins_at_errors
        expect(begins_at_errors.join(' ')).to include('required')
      else
        expect(msg).to include('input parameters not valid')
      end
    end
  end

  describe 'Update' do
    let!(:outage) do
      build_outage(
        state: :staged,
        begins_at: Time.utc(2026, 1, 10, 10, 0, 0),
        duration: 60,
        impact_type: :network
      )
    end

    it 'rejects unauthenticated access' do
      json_put show_path(outage.id), outage: { duration: 120 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users' do
      as(user) { json_put show_path(outage.id), outage: { duration: 120 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update outages' do
      as(admin) do
        json_put show_path(outage.id), outage: {
          duration: 120,
          impact: 'performance',
          en_summary: 'Updated summary'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      outage.reload
      expect(outage.duration).to eq(120)
      expect(outage.impact_type).to eq('performance')

      lang = ::Language.find_by(code: 'en')
      translation = ::OutageTranslation.find_by(outage: outage, language: lang)
      expect(translation.summary).to eq('Updated summary')
    end

    it 'returns 404 for missing outage' do
      as(admin) { json_put show_path(999_999), outage: { duration: 120 } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'RebuildAffectedVps' do
    let!(:outage) { build_outage(state: :staged) }

    it 'rejects unauthenticated access' do
      json_post rebuild_path(outage.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users' do
      as(user) { json_post rebuild_path(outage.id), {} }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to rebuild affected vpses' do
      as(admin) { json_post rebuild_path(outage.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Entity nested resource' do
    let!(:outage) { build_outage(state: :announced) }
    let!(:entity) { ::OutageEntity.create!(outage: outage, name: 'Node', row_id: SpecSeed.node.id) }

    it 'allows unauthenticated index access' do
      json_get entity_index_path(outage.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entities.map { |row| row['id'] }).to include(entity.id)
    end

    it 'allows unauthenticated show access' do
      json_get entity_show_path(outage.id, entity.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entity_obj['id']).to eq(entity.id)
    end

    it 'rejects unauthenticated create' do
      json_post entity_index_path(outage.id), entity: { name: 'Node', entity_id: SpecSeed.node.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users creating entities' do
      as(user) do
        json_post entity_index_path(outage.id), entity: { name: 'Node', entity_id: SpecSeed.node.id }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create entities' do
      as(admin) do
        json_post entity_index_path(outage.id), entity: { name: 'Location', entity_id: SpecSeed.location.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entity_obj['name']).to eq('Location')
    end

    it 'rejects duplicate entities' do
      as(admin) do
        json_post entity_index_path(outage.id), entity: { name: 'Node', entity_id: SpecSeed.node.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already exists')
    end

    it 'rejects unauthenticated delete' do
      json_delete entity_show_path(outage.id, entity.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users deleting entities' do
      as(user) { json_delete entity_show_path(outage.id, entity.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete entities' do
      as(admin) { json_delete entity_show_path(outage.id, entity.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::OutageEntity.where(id: entity.id)).to be_empty
    end

    it 'returns 404 for missing entity' do
      as(admin) { json_delete entity_show_path(outage.id, 999_999) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Handler nested resource' do
    let!(:outage) { build_outage(state: :announced) }
    let!(:handler) { ::OutageHandler.create!(outage: outage, user: admin, note: 'Initial note') }

    it 'allows unauthenticated index access' do
      json_get handler_index_path(outage.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handlers.map { |row| row['id'] }).to include(handler.id)
    end

    it 'allows unauthenticated show access' do
      json_get handler_show_path(outage.id, handler.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handler_obj['id']).to eq(handler.id)
    end

    it 'includes user for admins' do
      as(admin) { json_get handler_index_path(outage.id) }

      expect_status(200)
      expect(handlers.first['user']).to be_a(Hash)
    end

    it 'hides user for unauthenticated users' do
      json_get handler_index_path(outage.id)

      expect_status(200)
      expect(handlers.first).not_to have_key('user')
    end

    it 'rejects unauthenticated create' do
      json_post handler_index_path(outage.id), handler: { user: admin.id, note: 'Spec note' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users creating handlers' do
      as(user) { json_post handler_index_path(outage.id), handler: { user: admin.id, note: 'Spec note' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create handlers' do
      as(admin) { json_post handler_index_path(outage.id), handler: { user: other_user.id, note: 'Spec note' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handler_obj['note']).to eq('Spec note')
    end

    it 'rejects duplicate handlers' do
      as(admin) { json_post handler_index_path(outage.id), handler: { user: admin.id, note: 'Spec note' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already exists')
    end

    it 'rejects unauthenticated update' do
      json_put handler_show_path(outage.id, handler.id), handler: { note: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users updating handlers' do
      as(user) { json_put handler_show_path(outage.id, handler.id), handler: { note: 'Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update handlers' do
      as(admin) { json_put handler_show_path(outage.id, handler.id), handler: { note: 'Updated' } }

      expect_status(200)
      expect(json['status']).to be(true)

      handler.reload
      expect(handler.note).to eq('Updated')
    end

    it 'requires note on update' do
      as(admin) { json_put handler_show_path(outage.id, handler.id), handler: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      note_errors = errors['note']
      if note_errors
        expect(note_errors.join(' ')).to include('required')
      else
        expect(msg).to include('input parameters not valid')
      end
    end

    it 'rejects unauthenticated delete' do
      json_delete handler_show_path(outage.id, handler.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'rejects normal users deleting handlers' do
      as(user) { json_delete handler_show_path(outage.id, handler.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete handlers' do
      as(admin) { json_delete handler_show_path(outage.id, handler.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::OutageHandler.where(id: handler.id)).to be_empty
    end
  end
end
