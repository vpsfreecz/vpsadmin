# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::UserNamespaceMap' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    in_use_vps
  end

  def maps_index_path
    vpath('/user_namespace_maps')
  end

  def map_show_path(id)
    vpath("/user_namespace_maps/#{id}")
  end

  def entries_index_path(map_id)
    vpath("/user_namespace_maps/#{map_id}/entries")
  end

  def entry_show_path(map_id, entry_id)
    vpath("/user_namespace_maps/#{map_id}/entries/#{entry_id}")
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
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def maps
    json.dig('response', 'user_namespace_maps') || []
  end

  def map_obj
    json.dig('response', 'user_namespace_map') || json['response']
  end

  def entries
    json.dig('response', 'entries') || []
  end

  def entry_obj
    json.dig('response', 'entry') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
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

  def create_vps!(user:, node:, hostname:, user_namespace_map:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dataset_in_pool = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active,
      user_namespace_map: user_namespace_map
    )
  end

  let!(:user_ns) do
    UserNamespace.create!(
      user: SpecSeed.user,
      block_count: 0,
      offset: 100_000,
      size: 1_000
    )
  end
  let!(:other_ns) do
    UserNamespace.create!(
      user: SpecSeed.other_user,
      block_count: 0,
      offset: 200_000,
      size: 1_000
    )
  end

  let!(:user_map_a) { UserNamespaceMap.create_direct!(user_ns, 'User map A') }
  let!(:user_map_b) { UserNamespaceMap.create_direct!(user_ns, 'User map B') }
  let!(:other_map) { UserNamespaceMap.create_direct!(other_ns, 'Other map') }

  let!(:user_map_a_entry) do
    UserNamespaceMapEntry.create!(
      user_namespace_map: user_map_a,
      kind: :uid,
      vps_id: 0,
      ns_id: 0,
      count: 1
    )
  end
  let!(:other_map_entry) do
    UserNamespaceMapEntry.create!(
      user_namespace_map: other_map,
      kind: :uid,
      vps_id: 0,
      ns_id: 0,
      count: 1
    )
  end

  let!(:in_use_map) { UserNamespaceMap.create_direct!(user_ns, 'In use map') }
  let(:in_use_vps) do
    create_vps!(
      user: SpecSeed.user,
      node: SpecSeed.node,
      hostname: 'in-use-map-vps',
      user_namespace_map: in_use_map
    )
  end
  let!(:in_use_entry) do
    UserNamespaceMapEntry.create!(
      user_namespace_map: in_use_map,
      kind: :uid,
      vps_id: 0,
      ns_id: 2,
      count: 1
    )
  end

  describe 'API description' do
    it 'includes user namespace map endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user_namespace_map#index',
        'user_namespace_map#show',
        'user_namespace_map#create',
        'user_namespace_map#update',
        'user_namespace_map#delete',
        'user_namespace_map.entry#index',
        'user_namespace_map.entry#show',
        'user_namespace_map.entry#create',
        'user_namespace_map.entry#update',
        'user_namespace_map.entry#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get maps_index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only user-owned maps for normal users' do
      as(SpecSeed.user) { json_get maps_index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = maps.map { |row| row['id'] }
      expect(ids).to include(user_map_a.id, user_map_b.id)
      expect(ids).not_to include(other_map.id)
      row = maps.find { |map| map['id'] == user_map_a.id }
      expect(row).to include('id', 'label', 'user_namespace')
      expect(rid(row['user_namespace'])).to eq(user_ns.id)
    end

    it 'lists all maps for admin' do
      as(SpecSeed.admin) { json_get maps_index_path }

      expect_status(200)
      ids = maps.map { |row| row['id'] }
      expect(ids).to include(user_map_a.id, user_map_b.id, other_map.id)
    end

    it 'filters by user namespace' do
      as(SpecSeed.admin) { json_get maps_index_path, user_namespace_map: { user_namespace: user_ns.id } }

      expect_status(200)
      expect(maps).to all(satisfy { |row| rid(row['user_namespace']) == user_ns.id })
    end

    it 'filters by user for admin' do
      as(SpecSeed.admin) { json_get maps_index_path, user_namespace_map: { user: SpecSeed.other_user.id } }

      expect_status(200)
      ids = maps.map { |row| row['id'] }
      expect(ids).to eq([other_map.id])
    end

    it 'ignores user filter for non-admins' do
      as(SpecSeed.user) { json_get maps_index_path, user_namespace_map: { user: SpecSeed.other_user.id } }

      expect_status(200)
      ids = maps.map { |row| row['id'] }
      expect(ids).to include(user_map_a.id, user_map_b.id)
      expect(ids).not_to include(other_map.id)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get maps_index_path, user_namespace_map: { limit: 1 } }

      expect_status(200)
      expect(maps.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = UserNamespaceMap.order(:id).first.id
      as(SpecSeed.admin) { json_get maps_index_path, user_namespace_map: { from_id: boundary } }

      expect_status(200)
      ids = maps.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get map_show_path(user_map_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows user-owned map' do
      as(SpecSeed.user) { json_get map_show_path(user_map_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(map_obj).to include('id', 'label', 'user_namespace')
    end

    it 'does not show other user maps' do
      as(SpecSeed.user) { json_get map_show_path(other_map.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any map' do
      as(SpecSeed.admin) { json_get map_show_path(other_map.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown id' do
      as(SpecSeed.admin) { json_get map_show_path(0) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post maps_index_path, user_namespace_map: { user_namespace: user_ns.id, label: 'Spec map' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create map in their namespace' do
      label = "Spec map #{SecureRandom.hex(4)}"

      expect do
        as(SpecSeed.user) do
          json_post maps_index_path, user_namespace_map: { user_namespace: user_ns.id, label: label }
        end
      end.to change(UserNamespaceMap, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      map = UserNamespaceMap.find_by!(label: label)
      expect(map.user_namespace_id).to eq(user_ns.id)
    end

    it 'prevents user from creating map in other namespace' do
      expect do
        as(SpecSeed.user) do
          json_post maps_index_path, user_namespace_map: { user_namespace: other_ns.id, label: 'Nope' }
        end
      end.not_to change(UserNamespaceMap, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('access denied')
    end

    it 'allows admin to create map in any namespace' do
      label = "Admin map #{SecureRandom.hex(4)}"

      expect do
        as(SpecSeed.admin) do
          json_post maps_index_path, user_namespace_map: { user_namespace: other_ns.id, label: label }
        end
      end.to change(UserNamespaceMap, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserNamespaceMap.find_by!(label: label).user_namespace_id).to eq(other_ns.id)
    end

    it 'validates missing label' do
      as(SpecSeed.user) { json_post maps_index_path, user_namespace_map: { user_namespace: user_ns.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('label')
    end

    it 'validates missing user_namespace' do
      as(SpecSeed.user) { json_post maps_index_path, user_namespace_map: { label: 'Missing ns' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('user_namespace')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put map_show_path(user_map_a.id), user_namespace_map: { user_namespace: user_ns.id, label: 'New label' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to update own map label' do
      as(SpecSeed.user) do
        json_put map_show_path(user_map_a.id), user_namespace_map: { user_namespace: user_ns.id, label: 'New label' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_map_a.reload.label).to eq('New label')
    end

    it 'prevents user from updating other maps' do
      as(SpecSeed.user) do
        json_put map_show_path(other_map.id), user_namespace_map: { user_namespace: other_ns.id, label: 'Nope' }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update any map' do
      as(SpecSeed.admin) do
        json_put map_show_path(other_map.id), user_namespace_map: { user_namespace: other_ns.id, label: 'Admin edit' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(other_map.reload.label).to eq('Admin edit')
    end

    it 'validates missing label' do
      as(SpecSeed.admin) { json_put map_show_path(user_map_a.id), user_namespace_map: { user_namespace: user_ns.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('label')
    end

    it 'does not change user_namespace' do
      as(SpecSeed.admin) do
        json_put map_show_path(user_map_a.id), user_namespace_map: { user_namespace: other_ns.id, label: 'Rename' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_map_a.reload.user_namespace_id).to eq(user_ns.id)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete map_show_path(user_map_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to delete own unused map' do
      disposable_map = UserNamespaceMap.create_direct!(user_ns, 'Disposable')
      UserNamespaceMapEntry.create!(
        user_namespace_map: disposable_map,
        kind: :uid,
        vps_id: 0,
        ns_id: 0,
        count: 1
      )

      expect do
        as(SpecSeed.user) { json_delete map_show_path(disposable_map.id) }
      end.to change(UserNamespaceMap, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserNamespaceMapEntry.where(user_namespace_map_id: disposable_map.id).count).to eq(0)
    end

    it 'prevents user from deleting other maps' do
      as(SpecSeed.user) { json_delete map_show_path(other_map.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'blocks deletion when map is in use' do
      as(SpecSeed.user) { json_delete map_show_path(in_use_map.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('the map is in use')
      expect(UserNamespaceMap.where(id: in_use_map.id)).to exist
    end

    it 'allows admin to delete other user maps' do
      expect do
        as(SpecSeed.admin) { json_delete map_show_path(other_map.id) }
      end.to change(UserNamespaceMap, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'blocks admin deletion when map is in use' do
      as(SpecSeed.admin) { json_delete map_show_path(in_use_map.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('the map is in use')
      expect(UserNamespaceMap.where(id: in_use_map.id)).to exist
    end
  end

  describe 'Entry index' do
    it 'rejects unauthenticated access' do
      json_get entries_index_path(user_map_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists entries for user-owned map' do
      as(SpecSeed.user) { json_get entries_index_path(user_map_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = entries.map { |row| row['id'] }
      expect(ids).to include(user_map_a_entry.id)
    end

    it 'does not leak entries from other users' do
      as(SpecSeed.user) { json_get entries_index_path(other_map.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entries).to eq([])
    end

    it 'orders entries by kind then id' do
      order_map = UserNamespaceMap.create_direct!(user_ns, 'Order map')
      gid_entry = UserNamespaceMapEntry.create!(
        user_namespace_map: order_map,
        kind: :gid,
        vps_id: 0,
        ns_id: 20,
        count: 1
      )
      uid_entry = UserNamespaceMapEntry.create!(
        user_namespace_map: order_map,
        kind: :uid,
        vps_id: 0,
        ns_id: 10,
        count: 1
      )

      as(SpecSeed.user) { json_get entries_index_path(order_map.id) }

      expect_status(200)
      expect(entries.map { |row| row['id'] }).to eq([uid_entry.id, gid_entry.id])
    end
  end

  describe 'Entry show' do
    it 'rejects unauthenticated access' do
      json_get entry_show_path(user_map_a.id, user_map_a_entry.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows user-owned entry' do
      as(SpecSeed.user) { json_get entry_show_path(user_map_a.id, user_map_a_entry.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(entry_obj).to include('id', 'kind', 'vps_id', 'ns_id', 'count')
    end

    it 'does not show other user entry' do
      as(SpecSeed.user) { json_get entry_show_path(other_map.id, other_map_entry.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown entry' do
      as(SpecSeed.admin) { json_get entry_show_path(user_map_a.id, 0) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Entry create' do
    it 'rejects unauthenticated access' do
      json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: 0, count: 10 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'creates entry for user-owned map' do
      expect do
        as(SpecSeed.user) do
          json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: 1, count: 10 }
        end
      end.to change(UserNamespaceMapEntry, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      entry = UserNamespaceMapEntry.order(:id).last
      expect(entry.user_namespace_map_id).to eq(user_map_a.id)
      expect(entry.kind).to eq('uid')
      expect(entry.vps_id).to eq(0)
      expect(entry.ns_id).to eq(1)
      expect(entry.count).to eq(10)
    end

    it 'blocks create when map is in use' do
      expect do
        as(SpecSeed.user) do
          json_post entries_index_path(in_use_map.id), entry: { kind: 'uid', vps_id: 0, ns_id: 0, count: 1 }
        end
      end.not_to change(UserNamespaceMapEntry, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('the map is in use')
    end

    it 'enforces entry limit per kind' do
      limited_map = UserNamespaceMap.create_direct!(user_ns, 'Limited map')
      10.times do |idx|
        UserNamespaceMapEntry.create!(
          user_namespace_map: limited_map,
          kind: :uid,
          vps_id: 0,
          ns_id: idx,
          count: 1
        )
      end

      expect do
        as(SpecSeed.user) do
          json_post entries_index_path(limited_map.id), entry: { kind: 'uid', vps_id: 0, ns_id: 20, count: 1 }
        end
      end.not_to change(UserNamespaceMapEntry, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('maps are limited to 10 UID and 10 GID entries')
    end

    it 'validates kind' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'nope', vps_id: 0, ns_id: 0, count: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('kind')
    end

    it 'validates negative ns_id' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: -1, count: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('ns_id')
    end

    it 'validates negative vps_id' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: -1, ns_id: 0, count: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('vps_id')
    end

    it 'validates count greater than zero' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: 0, count: 0 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors).to include('count')
    end

    it 'validates ns_id within namespace size' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: 1_000, count: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('create failed')
      expect(errors).to include('ns_id')
    end

    it 'validates count within namespace size' do
      as(SpecSeed.user) do
        json_post entries_index_path(user_map_a.id), entry: { kind: 'uid', vps_id: 0, ns_id: 995, count: 10 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('create failed')
      expect(errors).to include('count')
    end
  end

  describe 'Entry update' do
    it 'rejects unauthenticated access' do
      json_put entry_show_path(user_map_a.id, user_map_a_entry.id), entry: { ns_id: 2, count: 5 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'updates entry for user-owned map' do
      as(SpecSeed.user) do
        json_put entry_show_path(user_map_a.id, user_map_a_entry.id), entry: { ns_id: 3, count: 2, vps_id: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      user_map_a_entry.reload
      expect(user_map_a_entry.ns_id).to eq(3)
      expect(user_map_a_entry.count).to eq(2)
      expect(user_map_a_entry.vps_id).to eq(1)
    end

    it 'blocks update when map is in use' do
      as(SpecSeed.user) do
        json_put entry_show_path(in_use_map.id, in_use_entry.id), entry: { ns_id: 5, count: 2 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('the map is in use')
    end

    it 'prevents user from updating other entries' do
      as(SpecSeed.user) do
        json_put entry_show_path(other_map.id, other_map_entry.id), entry: { ns_id: 2, count: 2 }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'validates update errors' do
      as(SpecSeed.user) do
        json_put entry_show_path(user_map_a.id, user_map_a_entry.id), entry: { ns_id: 1_000, count: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('update failed')
      expect(errors).to include('ns_id')
    end
  end

  describe 'Entry delete' do
    it 'rejects unauthenticated access' do
      json_delete entry_show_path(user_map_a.id, user_map_a_entry.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'deletes entry for user-owned map' do
      entry = UserNamespaceMapEntry.create!(
        user_namespace_map: user_map_a,
        kind: :uid,
        vps_id: 0,
        ns_id: 5,
        count: 1
      )

      expect do
        as(SpecSeed.user) { json_delete entry_show_path(user_map_a.id, entry.id) }
      end.to change(UserNamespaceMapEntry, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'blocks delete when map is in use' do
      as(SpecSeed.user) { json_delete entry_show_path(in_use_map.id, in_use_entry.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('the map is in use')
    end

    it 'prevents user from deleting other entries' do
      as(SpecSeed.user) { json_delete entry_show_path(other_map.id, other_map_entry.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
