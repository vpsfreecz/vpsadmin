# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Vps::StateLog' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    seed
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:support) { SpecSeed.support }
  let(:other_user) { SpecSeed.other_user }
  let(:seed) do
    base_time = Time.utc(2040, 1, 1, 12, 0, 0)
    dataset_in_pool = create_dataset_in_pool!(pool: SpecSeed.pool, user: user)

    vps_a = create_vps!(
      user: user,
      node: SpecSeed.node,
      hostname: "spec-vps-#{SecureRandom.hex(4)}",
      dataset_in_pool: dataset_in_pool
    )
    vps_b = create_vps!(
      user: other_user,
      node: SpecSeed.node,
      hostname: "spec-vps-#{SecureRandom.hex(4)}",
      dataset_in_pool: dataset_in_pool
    )

    auto_a = ObjectState.where(class_name: 'Vps', row_id: vps_a.id).order(:id).first
    auto_b = ObjectState.where(class_name: 'Vps', row_id: vps_b.id).order(:id).first

    auto_a.update_columns(created_at: base_time, updated_at: base_time)
    auto_b.update_columns(created_at: base_time, updated_at: base_time)

    a_suspended = ObjectState.create!(
      class_name: 'Vps',
      row_id: vps_a.id,
      state: :suspended,
      reason: 'Suspended for spec',
      user: admin,
      expiration_date: base_time + 3600,
      remind_after_date: base_time + 1800,
      created_at: base_time + 60,
      updated_at: base_time + 60
    )

    a_active_again = ObjectState.create!(
      class_name: 'Vps',
      row_id: vps_a.id,
      state: :active,
      reason: 'Reactivated for spec',
      user: admin,
      created_at: base_time + 120,
      updated_at: base_time + 120
    )

    b_suspended = ObjectState.create!(
      class_name: 'Vps',
      row_id: vps_b.id,
      state: :suspended,
      reason: 'Other vps log',
      user: admin,
      created_at: base_time + 180,
      updated_at: base_time + 180
    )

    {
      vps_a: vps_a,
      vps_b: vps_b,
      auto_a: auto_a,
      auto_b: auto_b,
      a_suspended: a_suspended,
      a_active_again: a_active_again,
      b_suspended: b_suspended
    }
  end

  def index_path(vps_id)
    vpath("/vpses/#{vps_id}/state_logs")
  end

  def show_path(vps_id, log_id)
    vpath("/vpses/#{vps_id}/state_logs/#{log_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def logs
    json.dig('response', 'state_logs')
  end

  def log_obj
    json.dig('response', 'state_log') || json['response']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  def create_dataset_in_pool!(pool:, user:)
    dataset = nil

    with_current_user(admin) do
      dataset = Dataset.create!(
        name: "spec-#{SecureRandom.hex(4)}",
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        object_state: :active
      )
    end

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:, dataset_in_pool:)
    with_current_user(admin) do
      Vps.create!(
        user: user,
        node: node,
        hostname: hostname,
        os_template: SpecSeed.os_template,
        dns_resolver: SpecSeed.dns_resolver,
        dataset_in_pool: dataset_in_pool,
        object_state: :active
      )
    end
  end

  describe 'API description' do
    it 'includes vps.state_log scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('vps.state_log#index', 'vps.state_log#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(seed[:vps_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get index_path(seed[:vps_a].id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) { json_get index_path(seed[:vps_a].id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin and returns ordered logs for the VPS' do
      as(admin) { json_get index_path(seed[:vps_a].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs).to be_an(Array)

      ids = logs.map { |row| row['id'] }
      expect(ids).to eq([seed[:auto_a].id, seed[:a_suspended].id, seed[:a_active_again].id])

      row = logs.find { |item| item['id'] == seed[:a_suspended].id }
      expect(row).to include('id', 'state', 'changed_at', 'expiration', 'remind_after', 'user', 'reason')
    end

    it 'returns only logs for the requested VPS' do
      as(admin) { json_get index_path(seed[:vps_b].id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = logs.map { |row| row['id'] }
      expect(ids).to contain_exactly(seed[:auto_b].id, seed[:b_suspended].id)
      expect(ids).not_to include(seed[:auto_a].id, seed[:a_suspended].id, seed[:a_active_again].id)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path(seed[:vps_a].id), state_log: { limit: 1 } }

      expect_status(200)
      expect(logs.length).to eq(1)
      expect(logs.first['id']).to eq(seed[:auto_a].id)
    end

    it 'supports from_id pagination' do
      as(admin) { json_get index_path(seed[:vps_a].id), state_log: { limit: 1, from_id: seed[:auto_a].id } }

      expect_status(200)
      expect(logs.length).to eq(1)
      expect(logs.first['id']).to eq(seed[:a_suspended].id)
    end

    it 'returns empty list for missing VPS id' do
      missing_vps_id = Vps.maximum(:id).to_i + 1000
      as(admin) { json_get index_path(missing_vps_id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs).to eq([])
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(seed[:vps_a].id, seed[:auto_a].id)

      expect_status(401)
    end

    it 'forbids normal users' do
      as(user) { json_get show_path(seed[:vps_a].id, seed[:auto_a].id) }

      expect_status(403)
    end

    it 'allows admin to show a log belonging to the VPS' do
      as(admin) { json_get show_path(seed[:vps_a].id, seed[:a_suspended].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(seed[:a_suspended].id)
      expect(log_obj['state']).to eq('suspended')
      expect(log_obj['reason']).to eq('Suspended for spec')
      expect(log_obj['user']).to be_a(Hash)
      expect(log_obj['user']['id']).to eq(admin.id)
    end

    it 'does not show log when VPS id does not match row_id' do
      as(admin) { json_get show_path(seed[:vps_a].id, seed[:b_suspended].id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'returns not found for unknown log id' do
      missing = ObjectState.maximum(:id).to_i + 100
      as(admin) { json_get show_path(seed[:vps_a].id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
