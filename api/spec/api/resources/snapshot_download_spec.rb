# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::SnapshotDownload' do
  def index_path
    vpath('/snapshot_downloads')
  end

  def show_path(id)
    vpath("/snapshot_downloads/#{id}")
  end

  def json_get(path, params = nil, env = {})
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }.merge(env)
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def downloads
    json.dig('response', 'snapshot_downloads') || []
  end

  def download_obj
    json.dig('response', 'snapshot_download') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def ensure_snapshot_download_base_url!
    cfg = SysConfig.find_or_initialize_by(category: 'core', name: 'snapshot_download_base_url')
    cfg.data_type ||= 'String'
    cfg.value = 'https://downloads.example.test'
    cfg.save! if cfg.changed?
  end

  def create_dataset!(user:, name:)
    Dataset.create!(
      user: user,
      name: name,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )
  end

  def create_dip!(dataset:, pool:)
    DatasetInPool.create!(
      dataset: dataset,
      pool: pool,
      mountpoint: "/#{dataset.full_name}"
    )
  end

  def create_snapshot!(dataset:, name:, history_id:, created_at:)
    Snapshot.create!(
      dataset: dataset,
      name: name,
      history_id: history_id,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def attach_snapshot_to_pool!(snapshot:, dip:)
    SnapshotInPool.create!(
      snapshot: snapshot,
      dataset_in_pool: dip
    )
  end

  def create_download!(user:, snapshot:, pool:, confirmed:, format: :archive, from_snapshot: nil)
    SnapshotDownload.create!(
      user: user,
      snapshot: snapshot,
      from_snapshot: from_snapshot,
      pool: pool,
      secret_key: SecureRandom.hex(16),
      file_name: "spec-#{snapshot.id}.tar.gz",
      confirmed: SnapshotDownload.confirmed(confirmed),
      format: format,
      object_state: :active,
      expiration_date: Time.now + 7.days
    )
  end

  let(:pool) { SpecSeed.pool }
  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  let!(:user_ds) { create_dataset!(user: user, name: "user-ds-#{SecureRandom.hex(4)}") }
  let!(:user_dip) { create_dip!(dataset: user_ds, pool: pool) }

  let!(:snap_old) { create_snapshot!(dataset: user_ds, name: 'snap-old', history_id: 123, created_at: Time.now - 2.days) }
  let!(:snap_new) { create_snapshot!(dataset: user_ds, name: 'snap-new', history_id: 123, created_at: Time.now - 1.day) }
  let!(:snap_other_history) do
    create_snapshot!(dataset: user_ds, name: 'snap-other', history_id: 999, created_at: Time.now - 3.days)
  end

  let!(:other_ds) { create_dataset!(user: other_user, name: "other-ds-#{SecureRandom.hex(4)}") }
  let!(:other_dip) { create_dip!(dataset: other_ds, pool: pool) }
  let!(:other_snap) do
    create_snapshot!(dataset: other_ds, name: 'other-snap', history_id: 333, created_at: Time.now - 4.days)
  end

  let!(:dl_user_pending) { create_download!(user: user, snapshot: snap_new, pool: pool, confirmed: :confirm_create) }
  let!(:dl_user_ready) { create_download!(user: user, snapshot: snap_old, pool: pool, confirmed: :confirmed) }
  let!(:dl_user_destroying) do
    create_download!(user: user, snapshot: snap_other_history, pool: pool, confirmed: :confirm_destroy)
  end
  let!(:dl_other_user) { create_download!(user: other_user, snapshot: other_snap, pool: pool, confirmed: :confirm_create) }

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    ensure_snapshot_download_base_url!
    attach_snapshot_to_pool!(snapshot: snap_old, dip: user_dip)
    attach_snapshot_to_pool!(snapshot: snap_new, dip: user_dip)
    attach_snapshot_to_pool!(snapshot: other_snap, dip: other_dip)
  end

  describe 'API description' do
    it 'includes snapshot download endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'snapshot_download#index',
        'snapshot_download#show',
        'snapshot_download#create',
        'snapshot_download#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only own downloads for normal user' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = downloads.map { |row| row['id'] }
      expect(ids).to include(dl_user_pending.id, dl_user_ready.id)
      expect(ids).not_to include(dl_other_user.id)
    end

    it 'excludes downloads in confirm_destroy state' do
      as(user) { json_get index_path }

      expect_status(200)
      ids = downloads.map { |row| row['id'] }
      expect(ids).not_to include(dl_user_destroying.id)
    end

    it 'allows admin to list all downloads except confirm_destroy' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = downloads.map { |row| row['id'] }
      expect(ids).to include(dl_user_pending.id, dl_user_ready.id, dl_other_user.id)
      expect(ids).not_to include(dl_user_destroying.id)
    end

    it 'filters by dataset' do
      as(SpecSeed.admin) do
        json_get index_path, snapshot_download: { dataset: user_ds.id }
      end

      expect_status(200)
      ids = downloads.map { |row| row['id'] }
      expect(ids).to include(dl_user_pending.id, dl_user_ready.id)
      expect(ids).not_to include(dl_user_destroying.id, dl_other_user.id)
    end

    it 'filters by snapshot' do
      as(SpecSeed.admin) do
        json_get index_path, snapshot_download: { snapshot: snap_new.id }
      end

      expect_status(200)
      ids = downloads.map { |row| row['id'] }
      expect(ids).to contain_exactly(dl_user_pending.id)
    end

    it 'paginates with limit' do
      as(SpecSeed.admin) do
        json_get index_path, snapshot_download: { limit: 1 }
      end

      expect_status(200)
      expect(downloads.length).to eq(1)
    end

    it 'paginates with from_id' do
      boundary = SnapshotDownload.order(:id).first.id

      as(SpecSeed.admin) do
        json_get index_path, snapshot_download: { from_id: boundary }
      end

      expect_status(200)
      ids = downloads.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'includes total_count when requested' do
      as(SpecSeed.admin) do
        json_get index_path, _meta: { count: true }
      end

      expect_status(200)
      expected = SnapshotDownload.where.not(
        confirmed: SnapshotDownload.confirmed(:confirm_destroy)
      ).count
      expect(json.dig('response', '_meta', 'total_count')).to eq(expected)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(dl_user_pending.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own download' do
      as(user) { json_get show_path(dl_user_pending.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(download_obj).to include('id', 'snapshot', 'format', 'file_name', 'url', 'ready', 'expiration_date')
      expect(download_obj['ready']).to be(false)
    end

    it 'returns 404 for other users' do
      as(user) { json_get show_path(dl_other_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any download' do
      as(SpecSeed.admin) { json_get show_path(dl_other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown id' do
      missing = SnapshotDownload.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, snapshot_download: { snapshot: snap_new.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'creates an archive download' do
      ensure_signer_unlocked!

      expect do
        as(user) do
          json_post index_path, snapshot_download: { snapshot: snap_new.id, send_mail: false }
        end
      end.to change(SnapshotDownload, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(download_obj['format']).to eq('archive')
      expect(download_obj['ready']).to be(false)
      expect(download_obj['url']).to include('https://downloads.example.test')
      expect(download_obj['url']).to include(download_obj['file_name'])

      created = SnapshotDownload.order(:id).last
      expect(created.user_id).to eq(user.id)
      expect(created.pool_id).to eq(pool.id)
      expect(created.snapshot_id).to eq(snap_new.id)
    end

    it 'creates an incremental_stream download with from_snapshot' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_new.id,
          from_snapshot: snap_old.id,
          format: 'incremental_stream',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      created = SnapshotDownload.order(:id).last
      expect(created.format).to eq('incremental_stream')
      expect(created.from_snapshot_id).to eq(snap_old.id)
    end

    it 'requires from_snapshot for incremental_stream' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_new.id,
          format: 'incremental_stream',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('from_snapshot is required')
    end

    it 'rejects from_snapshot for non-incremental formats' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_new.id,
          from_snapshot: snap_old.id,
          format: 'archive',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('from_snapshot is for incremental_stream format only')
    end

    it 'rejects history_id mismatches' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_new.id,
          from_snapshot: snap_other_history.id,
          format: 'incremental_stream',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('share the same history identifier')
    end

    it 'rejects from_snapshot that does not precede snapshot' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_old.id,
          from_snapshot: snap_new.id,
          format: 'incremental_stream',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('from_snapshot must precede snapshot')
    end

    it 'rejects snapshots already linked to downloads' do
      snap_with_link = create_snapshot!(
        dataset: user_ds,
        name: 'snap-linked',
        history_id: 123,
        created_at: Time.now - 5.hours
      )
      attach_snapshot_to_pool!(snapshot: snap_with_link, dip: user_dip)
      snap_with_link.update!(snapshot_download_id: dl_user_pending.id)

      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: { snapshot: snap_with_link.id, send_mail: false }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already been made available for download')
    end

    it 'prevents users from creating downloads for other users' do
      ensure_signer_unlocked!

      as(user) do
        json_post index_path, snapshot_download: { snapshot: other_snap.id, send_mail: false }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'rejects invalid format choice' do
      as(user) do
        json_post index_path, snapshot_download: {
          snapshot: snap_new.id,
          format: 'nope',
          send_mail: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys).to include('format')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(dl_user_pending.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to delete own download' do
      dl_to_delete = create_download!(
        user: user,
        snapshot: snap_new,
        pool: pool,
        confirmed: :confirm_create
      )

      ensure_signer_unlocked!

      as(user) { json_delete show_path(dl_to_delete.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(dl_to_delete.reload.confirmed).to eq(:confirm_destroy)

      as(user) { json_get index_path }
      ids = downloads.map { |row| row['id'] }
      expect(ids).not_to include(dl_to_delete.id)
    end

    it 'prevents user from deleting other users downloads' do
      ensure_signer_unlocked!

      as(user) { json_delete show_path(dl_other_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete any download' do
      dl_to_delete = create_download!(
        user: other_user,
        snapshot: other_snap,
        pool: pool,
        confirmed: :confirm_create
      )

      ensure_signer_unlocked!

      as(SpecSeed.admin) { json_delete show_path(dl_to_delete.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dl_to_delete.reload.confirmed).to eq(:confirm_destroy)
    end

    it 'returns 404 for unknown id' do
      missing = SnapshotDownload.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
