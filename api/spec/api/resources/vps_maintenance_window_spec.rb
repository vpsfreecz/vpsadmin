# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS::MaintenanceWindow' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path(vps)
    vpath("/vpses/#{vps.id}/maintenance_windows")
  end

  def show_path(vps, weekday)
    vpath("/vpses/#{vps.id}/maintenance_windows/#{weekday}")
  end

  alias_method :update_path, :show_path

  def update_all_path(vps)
    index_path(vps)
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def mw_list
    json.dig('response', 'maintenance_windows') || []
  end

  def mw_obj
    json.dig('response', 'maintenance_window') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dataset_in_pool = create_dataset_in_pool!(user: user, pool: pool)

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

  def seed_windows!(vps)
    (0..6).each do |wday|
      VpsMaintenanceWindow.create!(
        vps: vps,
        weekday: wday,
        is_open: true,
        opens_at: 0,
        closes_at: 24 * 60
      )
    end
  end

  let!(:user_vps) do
    vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    seed_windows!(vps)
    vps
  end

  let!(:other_vps) do
    vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'spec-other-vps')
    seed_windows!(vps)
    vps
  end

  describe 'API description' do
    it 'includes vps maintenance window endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'vps.maintenance_window#index',
        'vps.maintenance_window#show',
        'vps.maintenance_window#update',
        'vps.maintenance_window#update_all'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user_vps)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists maintenance windows for owned VPS' do
      as(SpecSeed.user) { json_get index_path(user_vps) }

      expect_status(200)
      expect(json['status']).to be(true)

      list = mw_list
      expect(list.length).to eq(7)
      expect(list.map { |row| row['weekday'] }).to eq([0, 1, 2, 3, 4, 5, 6])
      list.each do |row|
        expect(row.keys).to include('weekday', 'is_open', 'opens_at', 'closes_at')
      end
    end

    it 'hides other user VPS windows' do
      as(SpecSeed.user) { json_get index_path(other_vps) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list any VPS windows' do
      as(SpecSeed.admin) { json_get index_path(other_vps) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'supports limit pagination' do
      as(SpecSeed.user) { json_get index_path(user_vps), maintenance_window: { limit: 3 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mw_list.length).to eq(3)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_vps, 2)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a specific weekday window for owned VPS' do
      as(SpecSeed.user) { json_get show_path(user_vps, 2) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mw_obj['weekday']).to eq(2)
      expect(mw_obj['is_open']).to be(true)
      expect(mw_obj['opens_at']).to eq(0)
      expect(mw_obj['closes_at']).to eq(1440)
    end

    it 'hides other user VPS windows' do
      as(SpecSeed.user) { json_get show_path(other_vps, 2) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown weekday' do
      as(SpecSeed.user) { json_get show_path(user_vps, 99) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put update_path(user_vps, 1), maintenance_window: { is_open: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'prevents users from updating other VPS windows' do
      as(SpecSeed.user) { json_put update_path(other_vps, 1), maintenance_window: { is_open: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'rejects empty input' do
      as(SpecSeed.user) { json_put update_path(user_vps, 1), maintenance_window: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide parameters to change')
    end

    it 'closes a window when is_open is false' do
      as(SpecSeed.user) { json_put update_path(user_vps, 1), maintenance_window: { is_open: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mw_obj['weekday']).to eq(1)
      expect(mw_obj['is_open']).to be(false)
      expect(mw_obj['opens_at']).to be_nil
      expect(mw_obj['closes_at']).to be_nil

      window = VpsMaintenanceWindow.find_by!(vps: user_vps, weekday: 1)
      expect(window.is_open).to be(false)
      expect(window.opens_at).to be_nil
      expect(window.closes_at).to be_nil
      expect(ObjectHistory.where(tracked_object: user_vps, event_type: 'maintenance_window').exists?).to be(true)
    end

    it 'resizes a window with valid values' do
      as(SpecSeed.user) do
        json_put update_path(user_vps, 3), maintenance_window: { is_open: true, opens_at: 60, closes_at: 180 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mw_obj['weekday']).to eq(3)
      expect(mw_obj['is_open']).to be(true)
      expect(mw_obj['opens_at']).to eq(60)
      expect(mw_obj['closes_at']).to eq(180)

      window = VpsMaintenanceWindow.find_by!(vps: user_vps, weekday: 3)
      expect(window.is_open).to be(true)
      expect(window.opens_at).to eq(60)
      expect(window.closes_at).to eq(180)
    end

    it 'reports validation errors' do
      as(SpecSeed.user) do
        json_put update_path(user_vps, 4), maintenance_window: { is_open: true, opens_at: -1, closes_at: 180 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('update failed')
      expect(response_errors.keys.map(&:to_s)).to include('opens_at')
    end

    it 'blocks updates during maintenance for non-admins' do
      user_vps.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec lock'
      )

      as(SpecSeed.user) do
        json_put update_path(user_vps, 1), maintenance_window: { is_open: false }
      end

      expect_status(423)
      expect(json['status']).to be(false)
      expect(response_message).to include('Resource is under maintenance: spec lock')
    end

    it 'allows admin updates during maintenance' do
      user_vps.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec lock'
      )

      as(SpecSeed.admin) do
        json_put update_path(user_vps, 1), maintenance_window: { is_open: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'UpdateAll' do
    it 'rejects unauthenticated access' do
      json_put update_all_path(user_vps), maintenance_window: { is_open: true, opens_at: 60, closes_at: 180 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'updates all week days with valid input' do
      payload = { is_open: true, opens_at: 60, closes_at: 180 }

      as(SpecSeed.user) { json_put update_all_path(user_vps), maintenance_window: payload }

      expect_status(200)
      expect(json['status']).to be(true)

      list = mw_list
      expect(list.length).to eq(7)
      expect(list.map { |row| row['weekday'] }).to eq([0, 1, 2, 3, 4, 5, 6])
      list.each do |row|
        expect(row['is_open']).to be(true)
        expect(row['opens_at']).to eq(60)
        expect(row['closes_at']).to eq(180)
      end

      windows = VpsMaintenanceWindow.where(vps: user_vps).order(:weekday)
      expect(windows.count).to eq(7)
      windows.each do |window|
        expect(window.is_open).to be(true)
        expect(window.opens_at).to eq(60)
        expect(window.closes_at).to eq(180)
      end
      expect(ObjectHistory.where(tracked_object: user_vps, event_type: 'maintenance_windows').exists?).to be(true)
    end

    it 'rejects empty input' do
      as(SpecSeed.user) { json_put update_all_path(user_vps), maintenance_window: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide parameters to change')
    end

    it 'rejects updates that violate weekly minimum length' do
      as(SpecSeed.user) do
        json_put update_all_path(user_vps), maintenance_window: { is_open: true, opens_at: 0, closes_at: 60 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('update failed')
      expect(response_errors.keys.map(&:to_s)).to include('closes_at')
    end

    it 'blocks updates during maintenance for non-admins' do
      user_vps.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec lock'
      )

      as(SpecSeed.user) do
        json_put update_all_path(user_vps), maintenance_window: { is_open: true, opens_at: 60, closes_at: 180 }
      end

      expect_status(423)
      expect(json['status']).to be(false)
      expect(response_message).to include('Resource is under maintenance: spec lock')
    end

    it 'allows admin updates during maintenance' do
      user_vps.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec lock'
      )

      as(SpecSeed.admin) do
        json_put update_all_path(user_vps), maintenance_window: { is_open: true, opens_at: 60, closes_at: 180 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end
end
