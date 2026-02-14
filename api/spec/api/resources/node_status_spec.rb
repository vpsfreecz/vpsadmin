# frozen_string_literal: true

require 'time'

RSpec.describe 'VpsAdmin::API::Resources::Node::Status' do
  let(:t0) { Time.utc(2040, 1, 1, 12, 0, 0) }

  let!(:ns_a) do
    NodeStatus.create!(
      node: SpecSeed.node,
      uptime: 100,
      process_count: 10,
      cpus: 4,
      cpu_user: 0.1,
      cpu_system: 0.2,
      cpu_idle: 99.0,
      total_memory: 4096,
      used_memory: 1024,
      total_swap: 1024,
      used_swap: 128,
      arc_size: 111,
      arc_c: 222,
      arc_c_max: 333,
      arc_hitpercent: 88.8,
      vpsadmin_version: 'spec-1',
      kernel: 'spec-kernel',
      cgroup_version: :cgroup_v1,
      loadavg1: 0.01,
      loadavg5: 0.02,
      loadavg15: 0.03,
      created_at: t0 + 60
    )
  end

  let!(:ns_b) do
    NodeStatus.create!(
      node: SpecSeed.node,
      uptime: 200,
      vpsadmin_version: 'spec-2',
      kernel: 'spec-kernel',
      created_at: t0 + 120
    )
  end

  let!(:ns_c) do
    NodeStatus.create!(
      node: SpecSeed.node,
      uptime: 300,
      vpsadmin_version: 'spec-3',
      kernel: 'spec-kernel',
      created_at: t0 + 180
    )
  end

  let!(:ns_other) do
    NodeStatus.create!(
      node: SpecSeed.other_node,
      uptime: 999,
      vpsadmin_version: 'other',
      kernel: 'other-kernel',
      created_at: t0 + 240
    )
  end

  before do
    header 'Accept', 'application/json'
    SpecSeed.node
    SpecSeed.other_node
    ns_a
    ns_b
    ns_c
    ns_other
  end

  def index_path(node_id)
    vpath("/nodes/#{node_id}/statuses")
  end

  def show_path(node_id, status_id)
    vpath("/nodes/#{node_id}/statuses/#{status_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def statuses
    json.dig('response', 'statuses')
  end

  def status_obj
    json.dig('response', 'status') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes node.status scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('node.status#index', 'node.status#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(SpecSeed.node.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get index_path(SpecSeed.node.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get index_path(SpecSeed.node.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list statuses for the node' do
      as(SpecSeed.admin) { json_get index_path(SpecSeed.node.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses).to be_an(Array)

      ids = statuses.map { |row| row['id'] }
      expect(ids).to contain_exactly(ns_a.id, ns_b.id, ns_c.id)
      expect(ids).not_to include(ns_other.id)
    end

    it 'orders statuses by created_at desc' do
      as(SpecSeed.admin) { json_get index_path(SpecSeed.node.id) }

      expect_status(200)
      expect(statuses.first['id']).to eq(ns_c.id)
    end

    it 'filters by from datetime' do
      from = (t0 + 121).iso8601

      as(SpecSeed.admin) do
        json_get index_path(SpecSeed.node.id), status: { from: from }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = statuses.map { |row| row['id'] }
      expect(ids).to contain_exactly(ns_c.id)
    end

    it 'filters by to datetime' do
      to = (t0 + 121).iso8601

      as(SpecSeed.admin) do
        json_get index_path(SpecSeed.node.id), status: { to: to }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = statuses.map { |row| row['id'] }
      expect(ids).to contain_exactly(ns_a.id, ns_b.id)
    end

    it 'filters by from and to datetime' do
      from = (t0 + 61).iso8601
      to = (t0 + 179).iso8601

      as(SpecSeed.admin) do
        json_get index_path(SpecSeed.node.id), status: { from: from, to: to }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = statuses.map { |row| row['id'] }
      expect(ids).to contain_exactly(ns_b.id)
    end

    it 'supports pagination limit' do
      as(SpecSeed.admin) { json_get index_path(SpecSeed.node.id), status: { limit: 2 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.length).to eq(2)
    end

    it 'supports pagination from_id' do
      boundary = NodeStatus.where(node: SpecSeed.node).order(:id).first.id

      as(SpecSeed.admin) do
        json_get index_path(SpecSeed.node.id), status: { from_id: boundary }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to all(be > boundary)
    end

    it 'returns meta count' do
      as(SpecSeed.admin) { json_get index_path(SpecSeed.node.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(SpecSeed.node.node_statuses.count)
    end

    it 'returns validation errors for invalid datetime' do
      as(SpecSeed.admin) do
        json_get index_path(SpecSeed.node.id), status: { from: 'not-a-datetime' }
      end

      expect(last_response.status).to be < 500

      next unless last_response.status == 200

      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('from')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(SpecSeed.node.id, ns_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get show_path(SpecSeed.node.id, ns_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get show_path(SpecSeed.node.id, ns_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a status' do
      as(SpecSeed.admin) { json_get show_path(SpecSeed.node.id, ns_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(status_obj['id']).to eq(ns_a.id)
      expect(status_obj['uptime']).to eq(100)
      expect(status_obj['version']).to eq('spec-1')
      expect(status_obj['kernel']).to eq('spec-kernel')
      expect(status_obj['created_at']).not_to be_nil
    end

    it 'scopes status to node' do
      as(SpecSeed.admin) { json_get show_path(SpecSeed.node.id, ns_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false) if last_response.status == 200
    end

    it 'returns 404 for unknown status id' do
      missing = NodeStatus.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(SpecSeed.node.id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false) if last_response.status == 200
    end

    it 'returns 404 for unknown node id' do
      missing_node = Node.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing_node, ns_a.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false) if last_response.status == 200
    end
  end
end
