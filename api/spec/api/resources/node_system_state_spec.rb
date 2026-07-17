# frozen_string_literal: true

require 'time'

RSpec.describe 'VpsAdmin::API::Resources::NodeSystemState' do
  let(:node) { Node.find(SpecSeed.node.id) }

  let!(:older) do
    NodeSystemState.create!(
      node:,
      cpus: 4,
      total_memory: 4096,
      total_swap: 0,
      cgroup_version: :cgroup_v1,
      first_observed_at: t0,
      last_observed_at: t0 + 60,
      current: false
    )
  end

  let!(:current) do
    NodeSystemState.create!(
      node:,
      cpus: 8,
      total_memory: 8192,
      total_swap: 1024,
      cgroup_version: :cgroup_v2,
      first_observed_at: t0 + 120,
      last_observed_at: t0 + 180,
      current: true
    )
  end

  let!(:inactive) do
    inactive_node = Node.find(SpecSeed.other_node.id)
    inactive_node.update!(active: false)
    NodeSystemState.create!(
      node: inactive_node,
      cpus: 2,
      total_memory: 2048,
      total_swap: 0,
      cgroup_version: :cgroup_v2,
      first_observed_at: t0 + 240,
      last_observed_at: t0 + 240,
      current: true
    )
  end

  let!(:service) do
    service_node = Node.create!(
      location: node.location,
      name: "system-state-mailer-#{Node.maximum(:id).to_i + 1}",
      role: :mailer,
      ip_addr: '192.0.2.245',
      cpus: 1,
      total_memory: 512,
      total_swap: 0,
      active: true
    )
    NodeSystemState.create!(
      node: service_node,
      cpus: 1,
      total_memory: 512,
      total_swap: 0,
      cgroup_version: :cgroup_v2,
      first_observed_at: t0 + 300,
      last_observed_at: t0 + 300,
      current: true
    )
  end

  def t0 = Time.utc(2040, 1, 1, 12, 0, 0)

  before do
    header 'Accept', 'application/json'
    older
    current
    inactive
    service
  end

  def index_path(resource = 'node_system_states')
    vpath("/#{resource}")
  end

  def show_path(id, resource = 'node_system_states')
    vpath("/#{resource}/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def states(resource = 'node_system_states')
    json.dig('response', resource)
  end

  def state_obj(resource = 'node_system_state')
    json.dig('response', resource) || json['response']
  end

  def expect_status(code)
    message = "Expected #{code}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'exposes system and narrow cgroup scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'node_system_state#index',
        'node_system_state#show',
        'node_cgroup_state#index',
        'node_cgroup_state#show'
      )
    end
  end

  describe 'system-state index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
    end

    it 'lets members list active hosting Nodes newest first' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(states.map { |row| row['id'] }).to eq([current.id, older.id])
    end

    it 'lets support users list active hosting Nodes' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(states.map { |row| row['id'] }).to contain_exactly(older.id, current.id)
    end

    it 'lets admins include or select inactive Nodes' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(states.map { |row| row['id'] }).to include(older.id, current.id, inactive.id)
      expect(states.map { |row| row['id'] }).not_to include(service.id)

      as(SpecSeed.admin) do
        json_get index_path, node_system_state: { node_active: false }
      end

      expect_status(200)
      expect(states.map { |row| row['id'] }).to eq([inactive.id])
    end

    it 'filters by Node, current state, and overlapping observation window' do
      as(SpecSeed.admin) do
        json_get index_path, node_system_state: {
          node: node.id,
          current: false,
          from: (t0 + 30).iso8601,
          to: (t0 + 90).iso8601
        }
      end

      expect_status(200)
      expect(states.map { |row| row['id'] }).to eq([older.id])
    end

    it 'returns typed values' do
      as(SpecSeed.user) { json_get index_path }

      row = states.find { |item| item['id'] == current.id }
      expect(row).to include(
        'cpus' => 8,
        'total_memory' => 8192,
        'total_swap' => 1024,
        'cgroup_version' => 'cgroup_v2',
        'current' => true
      )
      expect(row['node']).not_to be_nil
      expect(row).not_to have_key('node_active')
      expect(row['first_observed_at']).not_to be_nil
      expect(row['last_observed_at']).not_to be_nil
    end

    it 'paginates by observation time when older rows have newer IDs' do
      reconstructed = NodeSystemState.create!(
        node:,
        cpus: 2,
        total_memory: 2048,
        total_swap: 0,
        cgroup_version: :cgroup_v1,
        first_observed_at: t0 - 60,
        last_observed_at: t0 - 30,
        current: false
      )

      as(SpecSeed.user) do
        json_get index_path, node_system_state: { node: node.id, limit: 2 }
      end
      expect_status(200)
      first_page = states
      expect(first_page.map { |row| row['id'] }).to eq([current.id, older.id])

      as(SpecSeed.user) do
        json_get index_path, node_system_state: {
          node: node.id,
          limit: 2,
          from_id: first_page.last.fetch('id')
        }
      end
      expect_status(200)
      expect(states.map { |row| row['id'] }).to eq([reconstructed.id])
    end
  end

  describe 'system-state show' do
    it 'lets members show active states but hides inactive states' do
      as(SpecSeed.user) { json_get show_path(current.id) }

      expect_status(200)
      expect(state_obj['id']).to eq(current.id)

      as(SpecSeed.user) { json_get show_path(inactive.id) }
      expect_status(404)
    end

    it 'lets admins show inactive states' do
      as(SpecSeed.admin) { json_get show_path(inactive.id) }

      expect_status(200)
      expect(state_obj['id']).to eq(inactive.id)
    end
  end

  describe 'cgroup-state projection' do
    it 'returns cgroup history without capacity fields' do
      as(SpecSeed.user) { json_get index_path('node_cgroup_states') }

      expect_status(200)
      row = states('node_cgroup_states').find { |item| item['id'] == current.id }
      expect(row).to include('cgroup_version' => 'cgroup_v2', 'current' => true)
      expect(row).not_to have_key('cpus')
      expect(row).not_to have_key('total_memory')
      expect(row).not_to have_key('total_swap')
    end

    it 'coalesces capacity-only changes into one cgroup period' do
      current.update!(current: false)
      capacity_change = NodeSystemState.create!(
        node:,
        cpus: 16,
        total_memory: 16_384,
        total_swap: 2048,
        cgroup_version: :cgroup_v2,
        first_observed_at: t0 + 240,
        last_observed_at: t0 + 300,
        current: true
      )

      as(SpecSeed.user) do
        json_get index_path('node_cgroup_states'), node_cgroup_state: { node: node.id }
      end

      expect_status(200)
      rows = states('node_cgroup_states')
      expect(rows.map { |row| row['id'] }).to contain_exactly(older.id, current.id)

      older_row = rows.find { |row| row['id'] == older.id }
      expect(older_row).to include('cgroup_version' => 'cgroup_v1', 'current' => false)
      expect(Time.iso8601(older_row['first_observed_at'])).to eq(older.first_observed_at)
      expect(Time.iso8601(older_row['last_observed_at'])).to eq(older.last_observed_at)

      current_row = rows.find { |row| row['id'] == current.id }
      expect(current_row).to include('cgroup_version' => 'cgroup_v2', 'current' => true)
      expect(Time.iso8601(current_row['first_observed_at'])).to eq(current.first_observed_at)
      expect(Time.iso8601(current_row['last_observed_at'])).to eq(capacity_change.last_observed_at)
    end

    it 'applies the same active-Node boundary to show' do
      as(SpecSeed.user) do
        json_get show_path(inactive.id, 'node_cgroup_states')
      end

      expect_status(404)

      as(SpecSeed.admin) do
        json_get show_path(inactive.id, 'node_cgroup_states')
      end

      expect_status(200)
      expect(state_obj('node_cgroup_state')['id']).to eq(inactive.id)
    end
  end
end
