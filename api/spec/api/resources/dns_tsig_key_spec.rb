# frozen_string_literal: true

require 'securerandom'
require 'base64'

RSpec.describe 'VpsAdmin::API::Resources::DnsTsigKey' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.support
    SpecSeed.user
    SpecSeed.other_user
  end

  def index_path
    vpath('/dns_tsig_keys')
  end

  def show_path(id)
    vpath("/dns_tsig_keys/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def keys
    json.dig('response', 'dns_tsig_keys') || []
  end

  def key_obj
    json.dig('response', 'dns_tsig_key') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def b64(bytes = 32)
    Base64.strict_encode64(Random.new.bytes(bytes))
  end

  def create_key!(user:, name:, algorithm: 'hmac-sha256', secret: nil)
    ::DnsTsigKey.create!(
      user: user,
      name: name,
      algorithm: algorithm,
      secret: secret || b64(32)
    )
  end

  def create_zone!(name:, user:, role: :forward_role, source: :external_source, enabled: true,
                   label: '', default_ttl: 3600, email: 'dns@example.test')
    ::DnsZone.create!(
      name: name,
      user: user,
      zone_role: role,
      zone_source: source,
      enabled: enabled,
      label: label,
      default_ttl: default_ttl,
      email: email
    )
  end

  let!(:user_key_a) do
    create_key!(
      user: SpecSeed.user,
      name: "#{SpecSeed.user.id}-spec-tsig-a",
      algorithm: 'hmac-sha256'
    )
  end

  let!(:user_key_b) do
    create_key!(
      user: SpecSeed.user,
      name: "#{SpecSeed.user.id}-spec-tsig-b",
      algorithm: 'hmac-sha512'
    )
  end

  let!(:other_key) do
    create_key!(
      user: SpecSeed.other_user,
      name: "#{SpecSeed.other_user.id}-spec-tsig-c",
      algorithm: 'hmac-sha256'
    )
  end

  let!(:support_key) do
    create_key!(
      user: SpecSeed.support,
      name: "#{SpecSeed.support.id}-spec-tsig-support",
      algorithm: 'hmac-sha256'
    )
  end

  let!(:system_key) do
    create_key!(
      user: nil,
      name: 'spec-tsig-system',
      algorithm: 'hmac-sha256'
    )
  end

  describe 'API description' do
    it 'includes dns tsig key endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dns_tsig_key#index',
        'dns_tsig_key#show',
        'dns_tsig_key#create',
        'dns_tsig_key#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists keys owned by the user' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(keys).to be_an(Array)

      ids = keys.map { |row| row['id'] }
      expect(ids).to include(user_key_a.id, user_key_b.id)
      expect(ids).not_to include(other_key.id)
      expect(ids).not_to include(support_key.id)

      row = keys.find { |item| item['id'] == user_key_a.id }
      expect(row).to include('id', 'name', 'algorithm', 'secret', 'user', 'created_at', 'updated_at')
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
    end

    it 'allows support to list keys (restricted to own)' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = keys.map { |row| row['id'] }
      expect(ids).to contain_exactly(support_key.id)
    end

    it 'allows admins to list all keys' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = keys.map { |row| row['id'] }
      expect(ids).to include(user_key_a.id, user_key_b.id, other_key.id, support_key.id)
    end

    it 'filters by user' do
      as(SpecSeed.admin) { json_get index_path, dns_tsig_key: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = keys.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_key_a.id, user_key_b.id)
    end

    it 'filters by algorithm' do
      as(SpecSeed.admin) { json_get index_path, dns_tsig_key: { algorithm: 'hmac-sha512' } }

      expect_status(200)
      ids = keys.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_key_b.id)
    end

    it 'filters by user when nil' do
      as(SpecSeed.admin) { json_get index_path, dns_tsig_key: { user: nil } }

      expect_status(200)
      ids = keys.map { |row| row['id'] }
      expect(ids).to contain_exactly(system_key.id)
    end

    it 'prevents users from filtering by other users' do
      as(SpecSeed.user) { json_get index_path, dns_tsig_key: { user: SpecSeed.other_user.id } }

      expect_status(200)
      expect(keys).to be_empty
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dns_tsig_key: { limit: 1 } }

      expect_status(200)
      expect(keys.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = ::DnsTsigKey.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_tsig_key: { from_id: boundary } }

      expect_status(200)
      ids = keys.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(::DnsTsigKey.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_key_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their key' do
      as(SpecSeed.user) { json_get show_path(user_key_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_obj['id']).to eq(user_key_a.id)
      expect(key_obj['name']).to eq(user_key_a.name)
      expect(key_obj['algorithm']).to eq(user_key_a.algorithm)
      expect(key_obj['secret']).to be_a(String)
      expect(Base64.strict_encode64(Base64.strict_decode64(key_obj['secret']))).to eq(key_obj['secret'])
      expect(rid(key_obj['user'])).to eq(SpecSeed.user.id)
    end

    it 'returns 404 for users accessing other keys' do
      as(SpecSeed.user) { json_get show_path(other_key.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any key' do
      as(SpecSeed.admin) { json_get show_path(other_key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown key' do
      missing = ::DnsTsigKey.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, dns_tsig_key: { name: 'spec-create' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to create their own key' do
      payload = { name: "spec-create-#{SecureRandom.hex(4)}" }
      record = nil

      expect do
        as(SpecSeed.user) { json_post index_path, dns_tsig_key: payload }
      end.to change(::DnsTsigKey, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::DnsTsigKey.find(key_obj['id'])
      expect(record.user_id).to eq(SpecSeed.user.id)
      expect(record.name).to start_with("#{SpecSeed.user.id}-")
      expect(record.algorithm).to eq('hmac-sha256')
      expect(Base64.strict_encode64(Base64.strict_decode64(record.secret))).to eq(record.secret)

      expect(key_obj['id']).to eq(record.id)
      expect(key_obj['name']).to eq(record.name)
      expect(key_obj['algorithm']).to eq(record.algorithm)
      expect(key_obj['secret']).to eq(record.secret)
    end

    it 'ignores user input when creating as non-admin' do
      payload = {
        name: "spec-create-blacklist-#{SecureRandom.hex(4)}",
        user: SpecSeed.other_user.id
      }

      expect do
        as(SpecSeed.user) { json_post index_path, dns_tsig_key: payload }
      end.to change(::DnsTsigKey, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::DnsTsigKey.find(key_obj['id'])
      expect(record.user_id).to eq(SpecSeed.user.id)
      expect(record.name).to start_with("#{SpecSeed.user.id}-")
    end

    it 'allows admins to create a key for a selected user' do
      payload = {
        name: "spec-admin-#{SecureRandom.hex(4)}",
        user: SpecSeed.other_user.id,
        algorithm: 'hmac-sha512'
      }

      expect do
        as(SpecSeed.admin) { json_post index_path, dns_tsig_key: payload }
      end.to change(::DnsTsigKey, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::DnsTsigKey.find(key_obj['id'])
      expect(record.user_id).to eq(SpecSeed.other_user.id)
      expect(record.name).to start_with("#{SpecSeed.other_user.id}-")
      expect(record.algorithm).to eq('hmac-sha512')
    end

    it 'fails admin create without user' do
      as(SpecSeed.admin) { json_post index_path, dns_tsig_key: { name: 'no-user' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('create failed')
      expect(errors.keys.map(&:to_s) & %w[user user_id]).not_to be_empty
    end

    it 'returns validation errors for invalid name' do
      as(SpecSeed.user) { json_post index_path, dns_tsig_key: { name: 'bad name!' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('name')
    end

    it 'rejects duplicate names' do
      base = "dup-#{SecureRandom.hex(4)}"

      as(SpecSeed.user) { json_post index_path, dns_tsig_key: { name: base } }
      expect_status(200)
      expect(json['status']).to be(true)

      as(SpecSeed.user) { json_post index_path, dns_tsig_key: { name: base } }
      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already exists')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(user_key_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to delete their key' do
      key = create_key!(
        user: SpecSeed.user,
        name: "#{SpecSeed.user.id}-delete-me",
        algorithm: 'hmac-sha256'
      )

      as(SpecSeed.user) { json_delete show_path(key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::DnsTsigKey.where(id: key.id)).to be_empty
    end

    it 'returns 404 for users deleting other keys' do
      as(SpecSeed.user) { json_delete show_path(other_key.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete any key' do
      key = create_key!(
        user: SpecSeed.other_user,
        name: "#{SpecSeed.other_user.id}-delete-admin",
        algorithm: 'hmac-sha256'
      )

      as(SpecSeed.admin) { json_delete show_path(key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::DnsTsigKey.where(id: key.id)).to be_empty
    end

    it 'rejects delete when key is in use' do
      key = create_key!(
        user: SpecSeed.user,
        name: "#{SpecSeed.user.id}-in-use",
        algorithm: 'hmac-sha256'
      )
      zone = create_zone!(
        name: "spec-transfer-#{SecureRandom.hex(4)}.example.test.",
        user: SpecSeed.user,
        source: :external_source,
        email: 'user@example.test'
      )
      host_id = ::HostIpAddress.maximum(:id).to_i + 100

      transfer = ::DnsZoneTransfer.new(
        dns_zone_id: zone.id,
        host_ip_address_id: host_id,
        peer_type: ::DnsZoneTransfer.peer_types[:primary_type],
        dns_tsig_key_id: key.id
      )
      transfer.save!(validate: false)

      as(SpecSeed.user) { json_delete show_path(key.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('is in use')
      expect(::DnsTsigKey.where(id: key.id)).not_to be_empty
    end
  end
end
