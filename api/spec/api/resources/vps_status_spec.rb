# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS::Status' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.support
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.os_template
    SpecSeed.dns_resolver
    SpecSeed.pool
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:support) { SpecSeed.support }
  let(:other_user) { SpecSeed.other_user }

  let(:fixtures) do
    now = Time.utc(2040, 1, 1, 12, 0, 0)

    user_map = create_user_namespace_map!(user: user, offset: 100_000)
    other_map = create_user_namespace_map!(user: other_user, offset: 200_000)

    user_dip = create_dataset_in_pool!(user: user, pool: SpecSeed.pool)
    other_dip = create_dataset_in_pool!(user: other_user, pool: SpecSeed.pool)

    vps_user = create_vps!(
      user: user,
      node: SpecSeed.node,
      hostname: 'spec-vps-1.test',
      dataset_in_pool: user_dip,
      user_namespace_map: user_map
    )
    vps_other = create_vps!(
      user: other_user,
      node: SpecSeed.node,
      hostname: 'spec-vps-2.test',
      dataset_in_pool: other_dip,
      user_namespace_map: other_map
    )

    s_old = create_status!(
      vps: vps_user,
      status: true,
      is_running: true,
      in_rescue_mode: false,
      uptime: 120,
      process_count: 10,
      cpus: 2,
      cpu_user: 1.2,
      cpu_system: 0.3,
      cpu_idle: 98.5,
      loadavg1: 0.4,
      loadavg5: 0.3,
      loadavg15: 0.2,
      total_memory: 2048,
      used_memory: 512,
      total_swap: 1024,
      used_swap: 128,
      total_diskspace: 50_000,
      used_diskspace: 20_000,
      created_at: now - 3.hours
    )
    s_mid = create_status!(
      vps: vps_user,
      status: false,
      is_running: true,
      in_rescue_mode: false,
      uptime: 180,
      process_count: 12,
      cpus: 2,
      cpu_user: 2.4,
      cpu_system: 0.8,
      cpu_idle: 96.8,
      loadavg1: 0.8,
      loadavg5: 0.7,
      loadavg15: 0.6,
      total_memory: 2048,
      used_memory: 700,
      total_swap: 1024,
      used_swap: 256,
      total_diskspace: 50_000,
      used_diskspace: 25_000,
      created_at: now - 2.hours
    )
    s_new = create_status!(
      vps: vps_user,
      status: true,
      is_running: false,
      in_rescue_mode: true,
      uptime: 240,
      process_count: 8,
      cpus: 2,
      cpu_user: 3.1,
      cpu_system: 0.5,
      cpu_idle: 96.4,
      loadavg1: 1.2,
      loadavg5: 1.1,
      loadavg15: 1.0,
      total_memory: 2048,
      used_memory: 900,
      total_swap: 1024,
      used_swap: 300,
      total_diskspace: 50_000,
      used_diskspace: 30_000,
      created_at: now - 1.hour
    )

    other_status = create_status!(
      vps: vps_other,
      status: true,
      is_running: true,
      in_rescue_mode: false,
      uptime: 60,
      process_count: 5,
      cpus: 4,
      cpu_user: 0.6,
      cpu_system: 0.2,
      cpu_idle: 99.2,
      loadavg1: 0.1,
      loadavg5: 0.1,
      loadavg15: 0.1,
      total_memory: 4096,
      used_memory: 256,
      total_swap: 2048,
      used_swap: 64,
      total_diskspace: 75_000,
      used_diskspace: 10_000,
      created_at: now - 30.minutes
    )

    {
      now: now,
      vps_user: vps_user,
      vps_other: vps_other,
      s_old: s_old,
      s_mid: s_mid,
      s_new: s_new,
      other_status: other_status
    }
  end

  def vps_user
    fixtures.fetch(:vps_user)
  end

  def vps_other
    fixtures.fetch(:vps_other)
  end

  def s_old
    fixtures.fetch(:s_old)
  end

  def s_mid
    fixtures.fetch(:s_mid)
  end

  def s_new
    fixtures.fetch(:s_new)
  end

  def other_status
    fixtures.fetch(:other_status)
  end

  def now
    fixtures.fetch(:now)
  end

  def index_path(vps_id)
    vpath("/vpses/#{vps_id}/statuses")
  end

  def show_path(vps_id, status_id)
    vpath("/vpses/#{vps_id}/statuses/#{status_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def statuses
    json.dig('response', 'statuses') || json.dig('response', 'vps_statuses') || []
  end

  def status_obj
    json.dig('response', 'status') || json.dig('response', 'vps_status') || {}
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  def create_user_namespace_map!(user:, offset:)
    user_ns = UserNamespace.create!(
      user: user,
      block_count: 0,
      offset: offset,
      size: 1_000
    )

    UserNamespaceMap.create_direct!(user_ns, "spec-map-#{SecureRandom.hex(4)}")
  end

  def create_dataset_in_pool!(user:, pool:)
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

  def create_vps!(user:, node:, hostname:, dataset_in_pool:, user_namespace_map:)
    with_current_user(admin) do
      Vps.create!(
        user: user,
        node: node,
        hostname: hostname,
        os_template: SpecSeed.os_template,
        dns_resolver: SpecSeed.dns_resolver,
        dataset_in_pool: dataset_in_pool,
        user_namespace_map: user_namespace_map,
        object_state: :active
      )
    end
  end

  def create_status!(attrs)
    VpsStatus.create!(attrs)
  end

  describe 'API description' do
    it 'includes vps status endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('vps.status#index', 'vps.status#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(vps_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to list statuses for own VPS' do
      as(user) { json_get index_path(vps_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = statuses.map { |row| row['id'] }
      expect(ids).to eq([s_new.id, s_mid.id, s_old.id])

      row = statuses.find { |item| item['id'] == s_new.id }
      expect(row).to include(
        'id', 'status', 'is_running', 'in_rescue_mode', 'uptime', 'process_count', 'cpus',
        'cpu_user', 'cpu_system', 'cpu_idle', 'loadavg1', 'loadavg5', 'loadavg15',
        'total_memory', 'used_memory', 'total_swap', 'used_swap', 'created_at'
      )
    end

    it 'hides other user VPSes from normal users' do
      as(user) { json_get index_path(vps_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'hides other user VPSes from support users' do
      as(support) { json_get index_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list statuses for any VPS' do
      as(admin) { json_get index_path(vps_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([other_status.id])
    end

    it 'filters by from date' do
      from = (now - 2.5.hours).iso8601

      as(user) { json_get index_path(vps_user.id), status: { from: from } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_new.id, s_mid.id])
    end

    it 'filters by to date' do
      to = (now - 1.5.hours).iso8601

      as(user) { json_get index_path(vps_user.id), status: { to: to } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_mid.id, s_old.id])
    end

    it 'filters by from and to date' do
      from = (now - 2.5.hours).iso8601
      to = (now - 1.5.hours).iso8601

      as(user) { json_get index_path(vps_user.id), status: { from: from, to: to } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_mid.id])
    end

    it 'filters by status when true' do
      as(user) { json_get index_path(vps_user.id), status: { status: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_new.id, s_old.id])
    end

    it 'filters by is_running when true' do
      as(user) { json_get index_path(vps_user.id), status: { is_running: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_mid.id, s_old.id])
    end

    it 'applies limit' do
      as(user) { json_get index_path(vps_user.id), status: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_new.id])

      as(user) { json_get index_path(vps_user.id), status: { limit: 2 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(statuses.map { |row| row['id'] }).to eq([s_new.id, s_mid.id])
    end

    it 'returns validation error for invalid datetime' do
      as(user) { json_get index_path(vps_user.id), status: { from: 'not-a-date' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('from')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(vps_user.id, s_new.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show a status from own VPS' do
      as(user) { json_get show_path(vps_user.id, s_new.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(status_obj['id']).to eq(s_new.id)
      expect(status_obj['status']).to be(true)
      expect(status_obj['is_running']).to be(false)
      expect(status_obj['uptime']).to eq(240)
      expect(status_obj['created_at']).not_to be_nil
    end

    it 'hides other user statuses from normal users' do
      as(user) { json_get show_path(vps_other.id, other_status.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any status' do
      as(admin) { json_get show_path(vps_other.id, other_status.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(status_obj['id']).to eq(other_status.id)
    end

    it 'returns 404 for unknown status id' do
      missing = VpsStatus.maximum(:id).to_i + 100

      as(admin) { json_get show_path(vps_user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
