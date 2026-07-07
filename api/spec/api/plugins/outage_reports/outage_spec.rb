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
      outage_type: :unplanned_outage,
      impact_type: :network,
      state: :staged,
      auto_resolve: true
    }
    create_outage_with_translation!(defaults.merge(attrs))
  end

  def create_outage_vps!(outage:, vps:, direct:)
    ::OutageVps.create!(
      outage: outage,
      vps: vps,
      user: vps.user,
      environment: vps.node.location.environment,
      location: vps.node.location,
      node: vps.node,
      direct: direct
    )
  end

  def create_outage_export!(outage:, export:)
    pool = export.dataset_in_pool.pool

    ::OutageExport.create!(
      outage: outage,
      export: export,
      user: export.user,
      environment: pool.node.location.environment,
      location: pool.node.location,
      node: pool.node
    )
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

    it 'hides affected resource counts from non-admin output' do
      outage = build_outage(state: :announced)
      direct_vps = create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-direct-count')
      indirect_vps = create_vps!(user: other_user, node: SpecSeed.other_node, hostname: 'spec-indirect-count')
      export = create_export!(user: other_user, pool: SpecSeed.other_pool, path: '/export/spec-count')

      create_outage_vps!(outage: outage, vps: direct_vps, direct: true)
      create_outage_vps!(outage: outage, vps: indirect_vps, direct: false)
      create_outage_export!(outage: outage, export: export)
      outage.set_affected_users

      json_get index_path

      expect_status(200)
      row = outages.find { |item| item['id'] == outage.id }
      expect(row).not_to include(
        'affected_user_count',
        'affected_direct_vps_count',
        'affected_indirect_vps_count',
        'affected_export_count',
        'auto_resolve'
      )

      as(admin) { json_get index_path }

      expect_status(200)
      row = outages.find { |item| item['id'] == outage.id }
      expect(row).to include(
        'affected_user_count' => 2,
        'affected_direct_vps_count' => 1,
        'affected_indirect_vps_count' => 1,
        'affected_export_count' => 1,
        'auto_resolve' => true
      )
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

    it 'ignores private affected resource filters for non-admin callers' do
      affected_vps = create_vps!(
        user: other_user,
        node: SpecSeed.other_node,
        hostname: 'spec-private-filter-vps'
      )
      affected_export = create_export!(
        user: other_user,
        pool: SpecSeed.other_pool,
        path: '/export/spec-private-filter'
      )
      affected_outage = build_outage(
        state: :announced,
        begins_at: Time.utc(2026, 1, 3, 12, 0, 0)
      )
      decoy_outage = build_outage(
        state: :announced,
        begins_at: Time.utc(2026, 1, 4, 12, 0, 0)
      )

      create_outage_vps!(outage: affected_outage, vps: affected_vps, direct: true)
      create_outage_export!(outage: affected_outage, export: affected_export)

      json_get index_path, outage: { vps: affected_vps.id }

      expect_status(200)
      expect(outages.map { |row| row['id'] }).to contain_exactly(
        affected_outage.id,
        decoy_outage.id
      )

      as(user) { json_get index_path, outage: { export: affected_export.id } }

      expect_status(200)
      expect(outages.map { |row| row['id'] }).to contain_exactly(
        affected_outage.id,
        decoy_outage.id
      )

      as(admin) { json_get index_path, outage: { vps: affected_vps.id } }

      expect_status(200)
      expect(outages.map { |row| row['id'] }).to contain_exactly(affected_outage.id)
    end

    it 'filters by affected user' do
      target = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 3, 12, 0, 0))
      other = build_outage(state: :announced, begins_at: Time.utc(2026, 1, 4, 12, 0, 0))

      ::OutageUser.create!(outage: target, user:, vps_count: 1, export_count: 0)
      ::OutageUser.create!(outage: other, user: other_user, vps_count: 1, export_count: 0)

      as(admin) { json_get index_path, outage: { user: user.id } }

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

    it 'hides affected resource counts from non-admin detail output' do
      outage = build_outage(state: :announced)
      vps = create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-show-count')

      create_outage_vps!(outage: outage, vps: vps, direct: true)
      outage.set_affected_users

      json_get show_path(outage.id)

      expect_status(200)
      expect(outage_obj).not_to include(
        'affected_user_count',
        'affected_direct_vps_count',
        'affected_indirect_vps_count',
        'affected_export_count',
        'auto_resolve'
      )

      as(admin) { json_get show_path(outage.id) }

      expect_status(200)
      expect(outage_obj).to include(
        'affected_user_count' => 1,
        'affected_direct_vps_count' => 1,
        'affected_indirect_vps_count' => 0,
        'affected_export_count' => 0,
        'auto_resolve' => true
      )
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
          type: 'unplanned_outage',
          impact: 'network',
          auto_resolve: true,
          en_summary: 'Spec outage',
          cs_summary: 'Spec vypadek',
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
      expect(outage_obj['type']).to eq('unplanned_outage')
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

      lang = ::Language.find_by(code: 'cs')
      translation = ::OutageTranslation.find_by(outage: created, language: lang)
      expect(translation).not_to be_nil
      expect(translation.summary).to eq('Spec vypadek')
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
        impact_type: :network,
        finished_at: Time.utc(2026, 1, 10, 11, 0, 0)
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

    it 'allows clearing begins_at and finished_at' do
      as(admin) do
        json_put show_path(outage.id), outage: {
          begins_at: nil,
          finished_at: nil
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      outage.reload
      expect(outage.begins_at).to be_nil
      expect(outage.finished_at).to be_nil
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

      row = entities.detect { |v| v['id'] == entity.id }
      expect(row).to include(
        'name' => 'Node',
        'entity_type' => 'node',
        'entity_id' => SpecSeed.node.id,
        'label' => SpecSeed.node.domain_name
      )
    end

    it 'allows unauthenticated show access' do
      json_get entity_show_path(outage.id, entity.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entity_obj['id']).to eq(entity.id)
      expect(entity_obj).to include(
        'name' => 'Node',
        'entity_type' => 'node',
        'entity_id' => SpecSeed.node.id,
        'label' => SpecSeed.node.domain_name
      )
    end

    it 'labels custom entities as custom' do
      custom = ::OutageEntity.create!(outage: outage, name: 'External router')

      json_get entity_show_path(outage.id, custom.id)

      expect_status(200)
      expect(entity_obj).to include(
        'name' => 'External router',
        'entity_type' => 'custom',
        'entity_id' => nil,
        'label' => 'External router'
      )
    end

    it 'hides staged outage entities from non-admin readers' do
      staged = build_outage(state: :staged)
      staged_entity = ::OutageEntity.create!(
        outage: staged,
        name: 'Node',
        row_id: SpecSeed.node.id
      )

      json_get entity_index_path(staged.id)

      expect_status(200)
      expect(entities.map { |row| row['id'] }).not_to include(staged_entity.id)

      json_get entity_show_path(staged.id, staged_entity.id)

      expect_status(404)
      expect(json['status']).to be(false)

      as(user) { json_get entity_show_path(staged.id, staged_entity.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(admin) { json_get entity_show_path(staged.id, staged_entity.id) }

      expect_status(200)
      expect(entity_obj['id']).to eq(staged_entity.id)
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
      expect(entity_obj['entity_type']).to eq('location')
      expect(entity_obj['label']).to eq(SpecSeed.location.label)
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

    it 'hides staged outage handlers from non-admin readers' do
      staged = build_outage(state: :staged)
      staged_handler = ::OutageHandler.create!(
        outage: staged,
        user: admin,
        note: 'Private staging note'
      )

      json_get handler_index_path(staged.id)

      expect_status(200)
      expect(handlers.map { |row| row['id'] }).not_to include(staged_handler.id)

      json_get handler_show_path(staged.id, staged_handler.id)

      expect_status(404)
      expect(json['status']).to be(false)

      as(user) { json_get handler_show_path(staged.id, staged_handler.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(admin) { json_get handler_show_path(staged.id, staged_handler.id) }

      expect_status(200)
      expect(handler_obj['id']).to eq(staged_handler.id)
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
