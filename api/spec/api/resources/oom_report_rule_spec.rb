# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::OomReportRule' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    fixtures
  end

  let(:fixtures) do
    user_vps = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    other_vps = create_vps_row!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-other-vps')

    user_rule_a = OomReportRule.create!(
      vps: user_vps,
      action: :notify,
      cgroup_pattern: 'user/a',
      hit_count: 0
    )
    user_rule_b = OomReportRule.create!(
      vps: user_vps,
      action: :ignore,
      cgroup_pattern: 'user/b',
      hit_count: 7
    )
    other_rule = OomReportRule.create!(
      vps: other_vps,
      action: :notify,
      cgroup_pattern: 'other/a',
      hit_count: 0
    )

    {
      user_vps: user_vps,
      other_vps: other_vps,
      user_rule_a: user_rule_a,
      user_rule_b: user_rule_b,
      other_rule: other_rule
    }
  end

  def user_vps
    fixtures.fetch(:user_vps)
  end

  def other_vps
    fixtures.fetch(:other_vps)
  end

  def user_rule_a
    fixtures.fetch(:user_rule_a)
  end

  def user_rule_b
    fixtures.fetch(:user_rule_b)
  end

  def other_rule
    fixtures.fetch(:other_rule)
  end

  def create_vps_row!(user:, node:, hostname:)
    vps = Vps.new(
      user_id: user.id,
      node_id: node.id,
      hostname: hostname,
      os_template_id: 1
    )

    vps.object_state =
      if Vps.respond_to?(:object_states) && Vps.object_states[:active]
        Vps.object_states[:active]
      else
        0
      end

    vps.save!(validate: false)
    vps
  end

  def index_path
    vpath('/oom_report_rules')
  end

  def show_path(id)
    vpath("/oom_report_rules/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def rules_list
    json.dig('response', 'oom_report_rules') || []
  end

  def rule_obj
    json.dig('response', 'oom_report_rule')
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def rule_ids
    rules_list.map { |row| row['id'] }
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

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes oom_report_rule endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'oom_report_rule#index',
        'oom_report_rule#show',
        'oom_report_rule#create',
        'oom_report_rule#update',
        'oom_report_rule#delete'
      )
    end

    it 'documents oom_report_rule inputs' do
      index_params = action_input_params('oom_report_rule', 'index')
      create_params = action_input_params('oom_report_rule', 'create')
      update_params = action_input_params('oom_report_rule', 'update')

      expect(index_params.keys).to include('vps')
      expect(create_params.keys).to include('vps', 'action', 'cgroup_pattern', 'hit_count')
      expect(update_params.keys).to include('vps', 'action', 'cgroup_pattern', 'hit_count')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns only rules for the current user in ascending order' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rule_ids).to eq([user_rule_a.id, user_rule_b.id].sort)
      expect(rule_ids).not_to include(other_rule.id)
      expect(rule_ids).to eq(rule_ids.sort)

      rule = rules_list.find { |row| row['id'] == user_rule_a.id }
      expect(rule).to be_a(Hash)
      expect(rule.keys).to include(
        'id',
        'vps',
        'action',
        'cgroup_pattern',
        'hit_count',
        'label',
        'created_at',
        'updated_at'
      )
    end

    it 'filters by vps and respects restrictions' do
      as(SpecSeed.user) { json_get index_path, oom_report_rule: { vps: user_vps.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rule_ids).to eq([user_rule_a.id, user_rule_b.id].sort)

      as(SpecSeed.user) { json_get index_path, oom_report_rule: { vps: other_vps.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rule_ids).to be_empty
    end

    it 'allows admin to see all rules' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rule_ids).to include(user_rule_a.id, user_rule_b.id, other_rule.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_rule_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows user-owned rule' do
      as(SpecSeed.user) { json_get show_path(user_rule_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rule_obj['id']).to eq(user_rule_a.id)
      expect(rule_obj['action']).to eq(user_rule_a.action)
      expect(rule_obj['cgroup_pattern']).to eq(user_rule_a.cgroup_pattern)
      expect(rule_obj['hit_count']).to eq(user_rule_a.hit_count)
      expect(rule_obj['label']).to include(user_rule_a.action, user_rule_a.cgroup_pattern)
    end

    it 'returns 404 for other user rule' do
      as(SpecSeed.user) { json_get show_path(other_rule.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to view other user rule' do
      as(SpecSeed.admin) { json_get show_path(other_rule.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for missing id' do
      missing_id = OomReportRule.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing_id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        vps: user_vps.id,
        action: 'notify',
        cgroup_pattern: 'user/new'
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, oom_report_rule: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create for own vps' do
      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload }

      expect_status(200)
      expect(json['status']).to be(true)

      record = OomReportRule.find_by!(vps: user_vps, cgroup_pattern: payload[:cgroup_pattern])
      expect(record.action).to eq('notify')
      expect(record.hit_count).to eq(0)
    end

    it 'prevents user from creating for other vps' do
      count_before = OomReportRule.count

      as(SpecSeed.user) do
        json_post index_path, oom_report_rule: payload.merge(vps: other_vps.id, cgroup_pattern: 'other/new')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
      expect(OomReportRule.count).to eq(count_before)
    end

    it 'allows admin to create for other vps' do
      as(SpecSeed.admin) do
        json_post index_path, oom_report_rule: payload.merge(vps: other_vps.id, cgroup_pattern: 'other/new')
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(OomReportRule.find_by(vps: other_vps, cgroup_pattern: 'other/new')).not_to be_nil
    end

    it 'returns validation errors for missing action' do
      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload.except(:action) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('action')
    end

    it 'returns validation errors for missing cgroup_pattern' do
      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload.except(:cgroup_pattern) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('cgroup_pattern')
    end

    it 'returns validation errors for missing vps' do
      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload.except(:vps) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('vps')
    end

    it 'rejects invalid action choice' do
      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload.merge(action: 'nope') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('action')
    end

    it 'rejects too long cgroup_pattern' do
      as(SpecSeed.user) do
        json_post index_path, oom_report_rule: payload.merge(cgroup_pattern: 'a' * 256)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/create failed|input parameters not valid/)
      expect(response_errors.keys.map(&:to_s)).to include('cgroup_pattern')
    end

    it 'rejects create when rule limit is exceeded' do
      now = Time.now
      rows = Array.new(101) do |i|
        {
          vps_id: user_vps.id,
          action: OomReportRule.actions.fetch('notify'),
          cgroup_pattern: "bulk/#{i}",
          hit_count: 0,
          created_at: now,
          updated_at: now
        }
      end
      OomReportRule.insert_all!(rows)

      as(SpecSeed.user) { json_post index_path, oom_report_rule: payload.merge(cgroup_pattern: 'user/limit') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('rule limit reached')
    end
  end

  describe 'Update' do
    let(:payload) do
      {
        action: 'ignore',
        cgroup_pattern: 'user/updated',
        hit_count: 123
      }
    end

    it 'rejects unauthenticated access' do
      json_put show_path(user_rule_a.id), oom_report_rule: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to update own rule' do
      as(SpecSeed.user) { json_put show_path(user_rule_a.id), oom_report_rule: payload }

      expect_status(200)
      expect(json['status']).to be(true)

      user_rule_a.reload
      expect(user_rule_a.action).to eq('ignore')
      expect(user_rule_a.cgroup_pattern).to eq('user/updated')
      expect(user_rule_a.hit_count).to eq(123)
    end

    it 'returns 404 when updating other user rule' do
      as(SpecSeed.user) { json_put show_path(other_rule.id), oom_report_rule: payload }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update other user rule' do
      as(SpecSeed.admin) { json_put show_path(other_rule.id), oom_report_rule: payload }

      expect_status(200)
      expect(json['status']).to be(true)

      other_rule.reload
      expect(other_rule.action).to eq('ignore')
      expect(other_rule.cgroup_pattern).to eq('user/updated')
      expect(other_rule.hit_count).to eq(123)
    end

    it 'rejects invalid action choice' do
      as(SpecSeed.user) { json_put show_path(user_rule_a.id), oom_report_rule: { action: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('action')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(user_rule_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to delete own rule' do
      as(SpecSeed.user) { json_delete show_path(user_rule_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(OomReportRule.find_by(id: user_rule_a.id)).to be_nil
    end

    it 'returns 404 when deleting other user rule' do
      as(SpecSeed.user) { json_delete show_path(other_rule.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete other user rule' do
      as(SpecSeed.admin) { json_delete show_path(other_rule.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(OomReportRule.find_by(id: other_rule.id)).to be_nil
    end

    it 'returns 404 for missing id' do
      missing_id = OomReportRule.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_delete show_path(missing_id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
