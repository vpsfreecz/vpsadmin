# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::SecurityAdvisory' do
  include CoreResourceSpecHelpers

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
    vpath('/security_advisories')
  end

  def show_path(id)
    vpath("/security_advisories/#{id}")
  end

  def publish_path(id)
    vpath("/security_advisories/#{id}/publish")
  end

  def cve_index_path
    vpath('/security_advisory_cves')
  end

  def cve_path(id)
    vpath("/security_advisory_cves/#{id}")
  end

  def node_status_index_path(advisory_id)
    vpath("/security_advisories/#{advisory_id}/node_statuses")
  end

  def node_status_path(advisory_id, status_id)
    vpath("/security_advisories/#{advisory_id}/node_statuses/#{status_id}")
  end

  def update_index_path
    vpath('/security_advisory_updates')
  end

  def update_path(id)
    vpath("/security_advisory_updates/#{id}")
  end

  def vps_index_path
    vpath('/vps_security_advisories')
  end

  def user_index_path
    vpath('/user_security_advisories')
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

  def security_advisories
    json.dig('response', 'security_advisories') || []
  end

  def security_advisory_obj
    json.dig('response', 'security_advisory') || json['response']
  end

  def node_statuses
    json.dig('response', 'node_statuses') || json.dig('response', 'security_advisory_node_statuses') || []
  end

  def node_status_obj
    json.dig('response', 'node_status') || json.dig('response', 'security_advisory_node_status') || json['response']
  end

  def security_advisory_cves
    json.dig('response', 'security_advisory_cves') || []
  end

  def security_advisory_cve_obj
    json.dig('response', 'security_advisory_cve') || json['response']
  end

  def security_advisory_updates
    json.dig('response', 'security_advisory_updates') || []
  end

  def security_advisory_update_obj
    json.dig('response', 'security_advisory_update') || json['response']
  end

  def vps_security_advisories
    json.dig('response', 'vps_security_advisories') || []
  end

  def user_security_advisories
    json.dig('response', 'user_security_advisories') || []
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def action_input_params(resource_name, action_name)
    header 'Accept', 'application/json'
    options vpath('/')
    expect(last_response.status).to eq(200)

    data = json
    data = data['response'] if data.is_a?(Hash) && data['response'].is_a?(Hash)

    resources = data['resources'] || {}
    action = resources.dig(resource_name.to_s, 'actions', action_name.to_s) || {}
    action.dig('input', 'parameters') || {}
  end

  def build_advisory(attrs = {}, cves: 'CVE-2026-1000')
    advisory = ::SecurityAdvisory.create!(
      {
        state: :draft,
        name: 'Spec Vulnerability',
        created_by: SpecSeed.admin
      }.merge(attrs)
    )
    advisory.update_cves!(cves)
    advisory.security_advisory_translations.create!(
      language: SpecSeed.language,
      summary: 'Spec advisory summary',
      description: 'Spec advisory description',
      response: 'Spec mitigation response'
    )
    advisory.reload
  end

  def add_mitigated_status!(advisory, node: SpecSeed.node)
    ::SecurityAdvisoryNodeStatus.create!(
      security_advisory: advisory,
      node: node,
      state: :mitigated,
      vulnerable_until: Time.utc(2026, 1, 1, 10, 0, 0),
      mitigated_since: Time.utc(2026, 1, 1, 10, 5, 0)
    )
  end

  def add_not_affected_status!(advisory, node: SpecSeed.other_node)
    ::SecurityAdvisoryNodeStatus.create!(
      security_advisory: advisory,
      node: node,
      state: :not_affected
    )
  end

  def make_publishable!(advisory)
    add_mitigated_status!(advisory, node: SpecSeed.node)
    add_not_affected_status!(advisory, node: SpecSeed.other_node)
  end

  def build_published_advisory
    advisory = build_advisory
    make_publishable!(advisory)
    advisory.publish!(published_by: SpecSeed.admin)
    advisory.reload
  end

  describe 'API description' do
    it 'includes security advisory endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'security_advisory#index',
        'security_advisory#show',
        'security_advisory#create',
        'security_advisory#update',
        'security_advisory#publish',
        'security_advisory#rebuild_affected_vps',
        'security_advisory_cve#index',
        'security_advisory_cve#show',
        'security_advisory_cve#create',
        'security_advisory_cve#update',
        'security_advisory_cve#delete',
        'security_advisory.node_status#index',
        'security_advisory.node_status#create',
        'security_advisory.node_status#update',
        'security_advisory.node_status#delete',
        'security_advisory_update#index',
        'security_advisory_update#show',
        'security_advisory_update#create',
        'security_advisory_update#update',
        'security_advisory_update#delete',
        'vps_security_advisory#index',
        'user_security_advisory#index'
      )
    end

    it 'documents security advisory form parameters' do
      advisory_params = action_input_params(:security_advisory, :create)
      publish_params = action_input_params(:security_advisory, :publish)
      cve_params = action_input_params(:security_advisory_cve, :create)
      update_params = action_input_params(:security_advisory_update, :create)

      expect(advisory_params.dig('published_at', 'description')).to include(
        'advisory publication time'
      )
      expect(advisory_params.dig('name', 'description')).to include(
        'well-known vulnerability name'
      )
      expect(advisory_params.dig('en_summary', 'description')).to include(
        'One-sentence public summary'
      )
      expect(advisory_params.dig('en_description', 'description')).to include(
        'affected systems'
      )
      expect(advisory_params.dig('en_response', 'description')).to include(
        'whether users need to take action'
      )
      expect(publish_params.dig('send_mail', 'description')).to include(
        'affected users are emailed'
      )
      expect(cve_params.dig('cve_id', 'description')).to include(
        'CVE-YYYY-NNNN'
      )
      expect(update_params.dig('state', 'description')).to include(
        'state change'
      )
      expect(update_params.dig('en_summary', 'description')).to include(
        'summary of this update'
      )
      expect(update_params.dig('en_message', 'description')).to include(
        'more details'
      )
      expect(update_params).not_to include('en_description', 'en_response')
    end
  end

  describe 'Index and show' do
    it 'shows only published advisories to public readers' do
      draft = build_advisory
      published = build_published_advisory

      json_get index_path

      expect_status(200)
      ids = security_advisories.map { |row| row['id'] }
      expect(ids).to include(published.id)
      expect(ids).not_to include(draft.id)

      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = security_advisories.map { |row| row['id'] }
      expect(ids).to include(draft.id, published.id)
    end

    it 'hides administrative counters from public output' do
      advisory = build_published_advisory

      json_get show_path(advisory.id)

      expect_status(200)
      expect(security_advisory_obj).to include(
        'id' => advisory.id,
        'state' => 'published'
      )
      expect(security_advisory_obj).not_to include(
        'cves',
        'cve_urls',
        'affected_user_count',
        'affected_vps_count',
        'created_by',
        'published_by'
      )

      as(SpecSeed.admin) { json_get show_path(advisory.id) }

      expect_status(200)
      expect(security_advisory_obj).to include(
        'affected_user_count',
        'affected_vps_count',
        'created_by',
        'published_by'
      )
    end
  end

  describe 'Create and update' do
    let(:payload) do
      {
        security_advisory: {
          name: 'Spec Kernel Bug',
          published_at: Time.utc(2026, 1, 1, 8, 0, 0).iso8601,
          en_summary: 'Spec kernel summary',
          cs_summary: 'Spec shrnuti kernelu',
          en_description: 'Spec kernel description',
          en_response: 'Spec kernel mitigation'
        }
      }
    end

    it 'requires admin access' do
      json_post index_path, payload

      expect_status(401)
      expect(json['status']).to be(false)

      as(SpecSeed.user) { json_post index_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create and update drafts' do
      as(SpecSeed.admin) { json_post index_path, payload }

      expect_status(200)
      expect(json).to include('status' => true)
      expect(security_advisory_obj).to include(
        'state' => 'draft',
        'name' => 'Spec Kernel Bug',
        'en_summary' => 'Spec kernel summary'
      )
      expect(security_advisory_obj).not_to include('cves', 'cve_urls')
      expect(Time.parse(security_advisory_obj.fetch('published_at')).utc).to eq(Time.utc(2026, 1, 1, 8, 0, 0))

      advisory_id = security_advisory_obj.fetch('id')

      as(SpecSeed.admin) do
        json_put show_path(advisory_id), security_advisory: {
          name: 'Renamed Spec Kernel Bug',
          published_at: Time.utc(2026, 1, 1, 9, 0, 0).iso8601,
          en_summary: 'Updated kernel summary',
          cs_summary: 'Aktualizovane shrnuti kernelu'
        }
      end

      expect_status(200)
      expect(json).to include('status' => true)
      expect(security_advisory_obj).to include(
        'name' => 'Renamed Spec Kernel Bug',
        'en_summary' => 'Updated kernel summary'
      )
      expect(Time.parse(security_advisory_obj.fetch('published_at')).utc).to eq(Time.utc(2026, 1, 1, 9, 0, 0))
    end
  end

  describe 'CVEs' do
    it 'allows admins to manage advisory CVEs' do
      advisory = build_advisory(cves: 'CVE-2026-1001')

      as(SpecSeed.admin) do
        json_post cve_index_path, security_advisory_cve: {
          security_advisory: advisory.id,
          cve_id: 'CVE-2026-1002'
        }
      end

      expect_status(200)
      expect(json).to include('status' => true)
      expect(security_advisory_cve_obj).to include(
        'security_advisory_id' => advisory.id,
        'cve_id' => 'CVE-2026-1002',
        'url' => 'https://www.cve.org/CVERecord?id=CVE-2026-1002'
      )
      cve_id = security_advisory_cve_obj.fetch('id')

      as(SpecSeed.admin) do
        json_get cve_index_path, security_advisory_cve: {
          security_advisory: advisory.id,
          cve: 'CVE-2026-1002'
        }
      end

      expect_status(200)
      expect(security_advisory_cves.map { |row| row['id'] }).to contain_exactly(cve_id)

      as(SpecSeed.admin) do
        json_put cve_path(cve_id), security_advisory_cve: {
          cve_id: 'CVE-2026-1003'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(security_advisory_cve_obj['cve_id']).to eq('CVE-2026-1003')

      as(SpecSeed.admin) { json_delete cve_path(cve_id) }

      expect_status(200)
      expect(json).to include('status' => true)
      expect(::SecurityAdvisoryCve.where(id: cve_id)).to be_empty
    end

    it 'rejects invalid and duplicate CVEs' do
      advisory = build_advisory(cves: 'CVE-2026-1001')

      as(SpecSeed.admin) do
        json_post cve_index_path, security_advisory_cve: {
          security_advisory: advisory.id,
          cve_id: 'not-a-cve'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors['cve_id'].join(' ')).to include('CVE-YYYY-NNNN')

      as(SpecSeed.admin) do
        json_post cve_index_path, security_advisory_cve: {
          security_advisory: advisory.id,
          cve_id: 'CVE-2026-1001'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors['cve_id'].join(' ')).to include('has already been taken')
    end

    it 'rejects CVEs for missing advisories' do
      missing = ::SecurityAdvisory.maximum(:id).to_i + 100

      as(SpecSeed.admin) do
        json_post cve_index_path, security_advisory_cve: {
          security_advisory: missing,
          cve_id: 'CVE-2026-1999'
        }
      end

      expect(json['status']).to be(false)
      expect(::SecurityAdvisoryCve.where(security_advisory_id: missing)).to be_empty
    end

    it 'limits public CVE lists to visible advisories' do
      draft = build_advisory(cves: 'CVE-2026-1001')
      published = build_published_advisory

      json_get cve_index_path

      expect_status(200)
      cves = security_advisory_cves.map { |row| row['cve_id'] }
      expect(cves).to include(published.cves)
      expect(cves).not_to include(draft.cves)

      as(SpecSeed.admin) { json_get cve_index_path }

      expect_status(200)
      cves = security_advisory_cves.map { |row| row['cve_id'] }
      expect(cves).to include(draft.cves, published.cves)
    end
  end

  describe 'Node statuses and publication' do
    it 'blocks publication without at least one CVE' do
      advisory = build_advisory
      advisory.security_advisory_cves.delete_all
      make_publishable!(advisory)

      as(SpecSeed.admin) { json_post publish_path(advisory.id), security_advisory: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors['base'].join(' ')).to include('at least one CVE')
    end

    it 'blocks publication until all node statuses are mitigated or not affected' do
      advisory = build_advisory

      as(SpecSeed.admin) { json_post publish_path(advisory.id), security_advisory: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors['base'].join(' ')).to include('missing node status')

      as(SpecSeed.admin) do
        json_post node_status_index_path(advisory.id), node_status: {
          node: SpecSeed.node.id,
          state: 'vulnerable'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      status_id = node_status_obj.fetch('id')

      as(SpecSeed.admin) { json_post publish_path(advisory.id), security_advisory: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors['base'].join(' ')).to include('unresolved node status')

      as(SpecSeed.admin) do
        json_put node_status_path(advisory.id, status_id), node_status: {
          state: 'mitigated',
          vulnerable_until: Time.utc(2026, 1, 1, 10, 0, 0).iso8601,
          mitigated_since: Time.utc(2026, 1, 1, 10, 5, 0).iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      add_not_affected_status!(advisory)
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-security-vps')

      published_at = Time.utc(2026, 1, 1, 11, 0, 0)
      as(SpecSeed.admin) do
        json_post publish_path(advisory.id), security_advisory: {
          send_mail: false,
          published_at: published_at.iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(security_advisory_obj['state']).to eq('published')
      expect(Time.parse(security_advisory_obj.fetch('published_at')).utc).to eq(published_at)

      snapshot = ::SecurityAdvisoryVps.find_by!(security_advisory: advisory, vps: user_vps)
      expect(snapshot.user).to eq(SpecSeed.user)
      expect(snapshot.node_state).to eq('mitigated')
    end

    it 'rejects node statuses for missing advisories' do
      missing = ::SecurityAdvisory.maximum(:id).to_i + 100

      as(SpecSeed.admin) do
        json_post node_status_index_path(missing), node_status: {
          node: SpecSeed.node.id,
          state: 'not_affected'
        }
      end

      expect_status(404)
      expect(json['status']).to be(false)
      expect(::SecurityAdvisoryNodeStatus.where(security_advisory_id: missing)).to be_empty
    end

    it 'lists node statuses publicly only for published advisories' do
      draft = build_advisory
      published = build_published_advisory
      draft_status = add_mitigated_status!(draft)

      json_get node_status_index_path(draft.id)

      expect_status(200)
      expect(node_statuses.map { |row| row['id'] }).not_to include(draft_status.id)

      json_get node_status_index_path(published.id)

      expect_status(200)
      expect(node_statuses.map { |row| row['node_id'] }).to include(SpecSeed.node.id)
    end
  end

  describe 'Affected resource indexes' do
    it 'limits affected VPS rows to the current user' do
      advisory = build_advisory
      make_publishable!(advisory)
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-security-user-vps')
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-security-other-vps')
      advisory.publish!(published_by: SpecSeed.admin)

      json_get vps_index_path

      expect_status(401)

      as(SpecSeed.user) { json_get vps_index_path }

      expect_status(200)
      rows = vps_security_advisories
      expect(rows.map { |row| resource_id(row['vps']) }).to contain_exactly(user_vps.id)
      expect(rows.first).not_to include('user')

      as(SpecSeed.admin) { json_get vps_index_path }

      expect_status(200)
      expect(vps_security_advisories.map { |row| resource_id(row['vps']) }).to include(user_vps.id, other_vps.id)
    end

    it 'lists only current user advisory summaries for normal users' do
      advisory = build_advisory
      make_publishable!(advisory)
      create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-security-user-summary')
      create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-security-other-summary')
      advisory.publish!(published_by: SpecSeed.admin)

      as(SpecSeed.user) { json_get user_index_path }

      expect_status(200)
      expect(user_security_advisories.size).to eq(1)
      expect(user_security_advisories.first['vps_count']).to eq(1)
      expect(user_security_advisories.first).not_to include('user')
    end

    it 'lets users filter advisory summaries by their own VPS' do
      advisory = build_advisory
      make_publishable!(advisory)
      user_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-security-user-filter')
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-security-other-filter')
      advisory.publish!(published_by: SpecSeed.admin)

      as(SpecSeed.user) { json_get index_path, security_advisory: { vps: user_vps.id } }

      expect_status(200)
      expect(security_advisories.map { |row| row['id'] }).to contain_exactly(advisory.id)

      as(SpecSeed.user) { json_get index_path, security_advisory: { vps: other_vps.id } }

      expect_status(200)
      expect(security_advisories).to be_empty
    end
  end

  describe 'Advisory updates' do
    it 'creates public updates without sending mail by default' do
      advisory = build_published_advisory
      published_at = Time.utc(2026, 1, 2, 12, 0, 0)
      allow(TransactionChains::SecurityAdvisories::Mail).to receive(:fire)

      as(SpecSeed.admin) do
        json_post update_index_path, security_advisory_update: {
          security_advisory: advisory.id,
          published_at: published_at.iso8601,
          en_summary: 'Follow-up summary',
          cs_summary: 'Navazujici shrnuti',
          en_message: 'Follow-up message'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(security_advisory_update_obj['en_summary']).to eq('Follow-up summary')
      expect(security_advisory_update_obj['en_message']).to eq('Follow-up message')
      expect(security_advisory_update_obj).not_to include('en_description', 'en_response')
      update_id = security_advisory_update_obj.fetch('id')
      expect(TransactionChains::SecurityAdvisories::Mail).not_to have_received(:fire)
      expect(advisory.reload.published_at.utc).to eq(published_at)

      json_get update_index_path, security_advisory_update: { security_advisory: advisory.id }

      expect_status(200)
      expect(security_advisory_updates.map { |row| row['id'] }).to include(update_id)
    end

    it 'rejects updates for missing advisories' do
      missing = ::SecurityAdvisory.maximum(:id).to_i + 100

      as(SpecSeed.admin) do
        json_post update_index_path, security_advisory_update: {
          security_advisory: missing,
          en_summary: 'Orphan update',
          cs_summary: 'Osamocena aktualizace'
        }
      end

      expect(json['status']).to be(false)
      expect(::SecurityAdvisoryUpdate.where(security_advisory_id: missing)).to be_empty
    end

    it 'requires update summaries and lets admins edit and delete update text' do
      advisory = build_published_advisory

      as(SpecSeed.admin) do
        json_post update_index_path, security_advisory_update: {
          security_advisory: advisory.id,
          en_message: 'Message without summary'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('en_summary')

      as(SpecSeed.admin) do
        json_post update_index_path, security_advisory_update: {
          security_advisory: advisory.id,
          en_summary: 'Editable update',
          cs_summary: 'Upravitelna aktualizace',
          en_message: ''
        }
      end

      expect_status(200)
      update_id = security_advisory_update_obj.fetch('id')
      expect(security_advisory_update_obj['en_message']).to be_nil

      as(SpecSeed.admin) do
        json_put update_path(update_id), security_advisory_update: {
          en_summary: 'Edited update',
          cs_summary: 'Upravena aktualizace',
          en_message: 'Edited update message'
        }
      end

      expect_status(200)
      expect(security_advisory_update_obj).to include(
        'en_summary' => 'Edited update',
        'en_message' => 'Edited update message'
      )

      json_get update_path(update_id)

      expect_status(200)
      expect(security_advisory_update_obj).to include(
        'en_summary' => 'Edited update',
        'en_message' => 'Edited update message'
      )

      as(SpecSeed.admin) { json_delete update_path(update_id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::SecurityAdvisoryUpdate.where(id: update_id)).to be_empty
      expect(::SecurityAdvisoryTranslation.where(security_advisory_update_id: update_id)).to be_empty
    end
  end
end
