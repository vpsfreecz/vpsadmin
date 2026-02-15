# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS::Mount' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.node
    SpecSeed.pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  # --- request path helpers ---
  def mounts_path(vps_id)
    vpath("/vpses/#{vps_id}/mounts")
  end

  def mount_path(vps_id, mount_id)
    vpath("/vpses/#{vps_id}/mounts/#{mount_id}")
  end

  # --- request helpers ---
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
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  # --- response helpers ---
  def mounts
    json.dig('response', 'mounts') ||
      json.dig('response', 'vps.mounts') ||
      json.dig('response', 'vps_mounts') || []
  end

  def mount_obj
    json.dig('response', 'mount') ||
      json.dig('response', 'vps.mount') ||
      json.dig('response', 'vps_mount') ||
      json['response']
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

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:, parent: nil, name_prefix: 'spec')
    Dataset.create!(
      name: "#{name_prefix}-#{SecureRandom.hex(4)}",
      user: user,
      parent: parent,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    ).tap do |ds|
      DatasetInPool.create!(dataset: ds, pool: pool)
    end
  end

  def dataset_in_pool_for(dataset, pool)
    dataset.dataset_in_pools.find_by!(pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    root_ds = create_dataset_in_pool!(user: user, pool: pool, name_prefix: 'vpsroot')

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool_for(root_ds, pool),
      object_state: :active
    )
  end

  def create_mountable_subdataset!(vps:, user:)
    pool = vps.dataset_in_pool.pool
    create_dataset_in_pool!(
      user: user,
      pool: pool,
      parent: vps.dataset_in_pool.dataset,
      name_prefix: 'mntds'
    )
  end

  def create_mount!(vps:, dip:, dst:, mode: 'rw', enabled: true, master_enabled: true, on_start_fail: :mount_later)
    Mount.create!(
      vps: vps,
      dst: dst,
      mount_opts: '--bind',
      umount_opts: '-f',
      mount_type: 'bind',
      user_editable: false,
      dataset_in_pool: dip,
      mode: mode,
      enabled: enabled,
      master_enabled: master_enabled,
      on_start_fail: on_start_fail,
      object_state: :active,
      confirmed: 0
    )
  end

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  def admin
    SpecSeed.admin
  end

  let(:fixtures) do
    user_vps = create_vps!(user: user, node: SpecSeed.node, hostname: 'spec-user-vps')
    other_vps = create_vps!(user: other_user, node: SpecSeed.node, hostname: 'spec-other-vps')

    mountable_dataset = create_mountable_subdataset!(vps: user_vps, user: user)
    mountable_dataset_b = create_mountable_subdataset!(vps: user_vps, user: user)
    other_mountable_dataset = create_mountable_subdataset!(vps: other_vps, user: other_user)

    mountable_dip = dataset_in_pool_for(mountable_dataset, user_vps.dataset_in_pool.pool)
    mountable_dip_b = dataset_in_pool_for(mountable_dataset_b, user_vps.dataset_in_pool.pool)
    other_mountable_dip = dataset_in_pool_for(other_mountable_dataset, other_vps.dataset_in_pool.pool)

    mnt_a = create_mount!(vps: user_vps, dip: mountable_dip, dst: '/mnt/a')
    mnt_b = create_mount!(vps: user_vps, dip: mountable_dip_b, dst: '/mnt/b')
    mnt_other = create_mount!(vps: other_vps, dip: other_mountable_dip, dst: '/mnt/other')

    foreign_dataset = create_dataset_in_pool!(
      user: other_user,
      pool: user_vps.dataset_in_pool.pool,
      name_prefix: 'foreign'
    )

    {
      user_vps: user_vps,
      other_vps: other_vps,
      mountable_dataset: mountable_dataset,
      mountable_dip: mountable_dip,
      mnt_a: mnt_a,
      mnt_b: mnt_b,
      mnt_other: mnt_other,
      foreign_dataset: foreign_dataset
    }
  end

  def user_vps
    fixtures.fetch(:user_vps)
  end

  def other_vps
    fixtures.fetch(:other_vps)
  end

  def mountable_dataset
    fixtures.fetch(:mountable_dataset)
  end

  def mountable_dip
    fixtures.fetch(:mountable_dip)
  end

  def mnt_a
    fixtures.fetch(:mnt_a)
  end

  def mnt_b
    fixtures.fetch(:mnt_b)
  end

  def mnt_other
    fixtures.fetch(:mnt_other)
  end

  def foreign_dataset
    fixtures.fetch(:foreign_dataset)
  end

  describe 'API description' do
    it 'includes vps.mount endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'vps.mount#index',
        'vps.mount#show',
        'vps.mount#create',
        'vps.mount#update',
        'vps.mount#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get mounts_path(user_vps.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists mounts for owned VPS' do
      as(user) { json_get mounts_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = mounts.map { |row| row['id'] }
      expect(ids).to include(mnt_a.id, mnt_b.id)
      expect(ids).not_to include(mnt_other.id)

      row = mounts.find { |item| item['id'] == mnt_a.id }
      expect(row).not_to be_nil
      expect(row.keys).to include(
        'id',
        'vps',
        'dataset',
        'mountpoint',
        'mode',
        'enabled',
        'master_enabled',
        'current_state'
      )
      expect(rid(row['vps'])).to eq(user_vps.id) if row['vps']
      expect(row['mountpoint']).to eq('/mnt/a')
    end

    it 'returns empty list when listing mounts of other users VPS' do
      as(user) { json_get mounts_path(other_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mounts).to eq([])
    end

    it 'allows admin to list mounts for any VPS' do
      as(admin) { json_get mounts_path(other_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = mounts.map { |row| row['id'] }
      expect(ids).to include(mnt_other.id)
    end

    it 'supports limit pagination' do
      as(user) { json_get mounts_path(user_vps.id), mount: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mounts.length).to eq(1)
    end

    it 'supports from_id pagination' do
      as(user) { json_get mounts_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = mounts.map { |row| row['id'] }
      from_id = ids.min

      as(user) { json_get mounts_path(user_vps.id), mount: { from_id: from_id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mounts.map { |row| row['id'] }).to all(be > from_id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get mount_path(user_vps.id, mnt_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows mount for owned VPS' do
      as(user) { json_get mount_path(user_vps.id, mnt_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mount_obj['id']).to eq(mnt_a.id)
      expect(rid(mount_obj['vps'])).to eq(user_vps.id) if mount_obj['vps']
      expect(mount_obj['mountpoint']).to eq('/mnt/a')
      expect(mount_obj['mode']).to eq('rw')
    end

    it 'hides mount from other users' do
      as(user) { json_get mount_path(other_vps.id, mnt_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when mount does not belong to VPS' do
      as(user) { json_get mount_path(user_vps.id, mnt_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post mounts_path(user_vps.id), mount: { dataset: mountable_dataset.id, mountpoint: '/mnt/new' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to create a mount for subdataset' do
      ensure_signer_unlocked!
      fixtures

      expect do
        as(user) do
          json_post mounts_path(user_vps.id),
                    mount: { dataset: mountable_dataset.id, mountpoint: '/mnt/new', mode: 'rw' }
        end
      end.to change(Mount, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      chain_id = action_state_id.to_i
      expect(chain_id).to be > 0
      expect(TransactionChain.find(chain_id)).not_to be_nil

      created_mount = Mount.find_by!(vps: user_vps, dst: '/mnt/new')
      expect(created_mount.dataset_in_pool.dataset_id).to eq(mountable_dataset.id)
      expect(created_mount.mode).to eq('rw')
    end

    it 'rejects mounting datasets owned by other users' do
      as(user) do
        json_post mounts_path(user_vps.id),
                  mount: { dataset: foreign_dataset.id, mountpoint: '/mnt/x' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('insufficient permission to mount selected snapshot')
    end

    it 'rejects datasets that are not VPS subdatasets' do
      independent_dataset = create_dataset_in_pool!(
        user: user,
        pool: user_vps.dataset_in_pool.pool,
        name_prefix: 'independent'
      )

      as(user) do
        json_post mounts_path(user_vps.id),
                  mount: { dataset: independent_dataset.id, mountpoint: '/mnt/y' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('Only VPS subdatasets can be mouted using vpsAdmin')
    end

    it 'validates mountpoint format' do
      as(user) do
        json_post mounts_path(user_vps.id),
                  mount: { dataset: mountable_dataset.id, mountpoint: '/../bad' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('create failed')
      expect(errors.keys.map(&:to_s)).to(
        satisfy { |keys| keys.include?('dst') || keys.include?('mountpoint') }
      )
    end

    it 'validates duplicate mountpoints' do
      create_mount!(vps: user_vps, dip: mountable_dip, dst: '/mnt/dup')

      as(user) do
        json_post mounts_path(user_vps.id),
                  mount: { dataset: mountable_dataset.id, mountpoint: '/mnt/dup' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('dst')
    end

    it 'validates mode choices' do
      as(user) do
        json_post mounts_path(user_vps.id),
                  mount: { dataset: mountable_dataset.id, mountpoint: '/mnt/mode', mode: 'nope' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('mode')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put mount_path(user_vps.id, mnt_a.id), mount: { enabled: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to update enabled' do
      ensure_signer_unlocked!

      as(user) { json_put mount_path(user_vps.id, mnt_a.id), mount: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(mnt_a.reload.enabled).to be(false)
    end

    it 'allows owner to update on_start_fail' do
      ensure_signer_unlocked!

      as(user) { json_put mount_path(user_vps.id, mnt_a.id), mount: { on_start_fail: 'skip' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(mnt_a.reload.on_start_fail).to eq('skip')
    end

    it 'ignores master_enabled updates for non-admins' do
      ensure_signer_unlocked!

      as(user) { json_put mount_path(user_vps.id, mnt_a.id), mount: { master_enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mnt_a.reload.master_enabled).to be(true)
    end

    it 'allows admin to update master_enabled' do
      ensure_signer_unlocked!

      as(admin) { json_put mount_path(user_vps.id, mnt_a.id), mount: { master_enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mnt_a.reload.master_enabled).to be(false)
    end

    it 'hides mounts on other VPSes from normal users' do
      as(user) { json_put mount_path(other_vps.id, mnt_other.id), mount: { enabled: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update mounts on other VPSes' do
      ensure_signer_unlocked!

      as(admin) { json_put mount_path(other_vps.id, mnt_other.id), mount: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mnt_other.reload.enabled).to be(false)
    end

    it 'blocks updates during maintenance for normal users' do
      MaintenanceLock.lock_for(user_vps, user: SpecSeed.admin, reason: 'Spec lock').lock!(user_vps)

      as(user) { json_put mount_path(user_vps.id, mnt_a.id), mount: { enabled: false } }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(msg).to include('Resource is under maintenance')
    end

    it 'allows admin to update during maintenance' do
      MaintenanceLock.lock_for(user_vps, user: SpecSeed.admin, reason: 'Spec lock').lock!(user_vps)
      ensure_signer_unlocked!

      as(admin) { json_put mount_path(user_vps.id, mnt_a.id), mount: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mnt_a.reload.enabled).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete mount_path(user_vps.id, mnt_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to delete a mount' do
      ensure_signer_unlocked!

      as(user) { json_delete mount_path(user_vps.id, mnt_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(mnt_a.reload.confirmed).to eq(:confirm_destroy)
    end

    it 'hides other user mounts from delete' do
      as(user) { json_delete mount_path(other_vps.id, mnt_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete any mount' do
      ensure_signer_unlocked!

      as(admin) { json_delete mount_path(other_vps.id, mnt_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mnt_other.reload.confirmed).to eq(:confirm_destroy)
    end

    it 'blocks deletes during maintenance for normal users' do
      MaintenanceLock.lock_for(user_vps, user: SpecSeed.admin, reason: 'Spec lock').lock!(user_vps)

      as(user) { json_delete mount_path(user_vps.id, mnt_a.id) }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(msg).to include('Resource is under maintenance')
    end
  end
end
