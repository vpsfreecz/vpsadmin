# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Dataset snapshot actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
  end

  let(:pool) do
    SpecSeed.pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  let!(:dataset_data) do
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "snap-root-#{SecureRandom.hex(4)}"
    )
  end

  let(:dataset) { dataset_data.first }
  let(:dip) { dataset_data.last }

  def snapshots_path(dataset_id)
    vpath("/datasets/#{dataset_id}/snapshots")
  end

  def snapshot_path(dataset_id, snapshot_id)
    vpath("/datasets/#{dataset_id}/snapshots/#{snapshot_id}")
  end

  def rollback_path(dataset_id, snapshot_id)
    vpath("/datasets/#{dataset_id}/snapshots/#{snapshot_id}/rollback")
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

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def snapshots
    json.dig('response', 'snapshots') || json.dig('response', 'dataset_snapshots') || []
  end

  def snapshot_obj
    json.dig('response', 'snapshot') || json.dig('response', 'dataset_snapshot')
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get snapshots_path(dataset.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists snapshots for dataset owner' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_get snapshots_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = snapshots.map { |row| row['id'] }
      expect(ids).to include(snap.id)
    end

    it 'returns empty list for other users' do
      create_snapshot!(dataset: dataset, dip: dip)

      as(other_user) { json_get snapshots_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(snapshots).to be_empty
    end

    it 'allows admin to list snapshots' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(SpecSeed.admin) { json_get snapshots_path(dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = snapshots.map { |row| row['id'] }
      expect(ids).to include(snap.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)
      json_get snapshot_path(dataset.id, snap.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own snapshot' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_get snapshot_path(dataset.id, snap.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(snapshot_obj['id']).to eq(snap.id)
    end

    it 'returns 404 for other users' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(other_user) { json_get snapshot_path(dataset.id, snap.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post snapshots_path(dataset.id), snapshot: { label: 'test' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create snapshot' do
      ensure_signer_unlocked!

      expect do
        as(user) { json_post snapshots_path(dataset.id), snapshot: { label: 'test' } }
      end.to change { Snapshot.where(dataset: dataset).count }.by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end

    it 'rejects create when too many snapshots exist' do
      dip.update!(max_snapshots: 1)
      create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_post snapshots_path(dataset.id), snapshot: { label: 'another' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/cannot make more than/i)
    end

    it 'allows user to create snapshot when dataset is not editable' do
      ensure_signer_unlocked!
      dataset.update!(user_editable: false)

      expect do
        as(user) { json_post snapshots_path(dataset.id), snapshot: { label: 'test' } }
      end.to change { Snapshot.where(dataset: dataset).count }.by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)
      json_delete snapshot_path(dataset.id, snap.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows deletion when dataset is not destroyable' do
      ensure_signer_unlocked!
      dataset.update!(user_destroy: false)
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_delete snapshot_path(dataset.id, snap.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end

    it 'rejects delete when snapshot has references' do
      snap, sip = create_snapshot!(dataset: dataset, dip: dip)
      sip.update!(reference_count: 1)

      as(user) { json_delete snapshot_path(dataset.id, snap.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/depending on it/i)
    end

    it 'rejects delete when dataset has backups' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      backup_pool = Pool.new(
        node: pool.node,
        label: "Backup Pool #{SecureRandom.hex(3)}",
        filesystem: "backup_pool_#{SecureRandom.hex(3)}",
        role: :backup,
        is_open: true
      ).tap(&:save!)
      DatasetInPool.create!(
        dataset: dataset,
        pool: backup_pool,
        confirmed: DatasetInPool.confirmed(:confirmed)
      )

      as(user) { json_delete snapshot_path(dataset.id, snap.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/cannot destroy snapshot with backups/i)
    end

    it 'creates transaction chain on successful delete' do
      ensure_signer_unlocked!
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_delete snapshot_path(dataset.id, snap.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end
  end

  describe 'Rollback' do
    it 'rejects unauthenticated access' do
      snap, = create_snapshot!(dataset: dataset, dip: dip)
      json_post rollback_path(dataset.id, snap.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows rollback when dataset is not editable' do
      ensure_signer_unlocked!
      dataset.update!(user_editable: false)
      snap, = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_post rollback_path(dataset.id, snap.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end

    it 'rolls back to older snapshot' do
      ensure_signer_unlocked!
      older_snap, older_sip = create_snapshot!(dataset: dataset, dip: dip)
      newer_snap, newer_sip = create_snapshot!(dataset: dataset, dip: dip)

      as(user) { json_post rollback_path(dataset.id, older_snap.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(newer_sip.reload.confirmed).to eq(:confirm_destroy)
      expect(older_sip.reload.confirmed).to eq(:confirmed)
      expect(newer_snap.reload.confirmed).to eq(:confirm_destroy)
    end

    it 'rejects rollback when newer snapshots are in use' do
      older_snap, = create_snapshot!(dataset: dataset, dip: dip)
      newer_snap, newer_sip = create_snapshot!(dataset: dataset, dip: dip)
      newer_sip.update!(reference_count: 1)

      as(user) { json_post rollback_path(dataset.id, older_snap.id), {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/in use/i)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
