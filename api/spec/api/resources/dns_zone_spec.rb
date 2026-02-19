# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsZone' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
  end

  def index_path
    vpath('/dns_zones')
  end

  def show_path(id)
    vpath("/dns_zones/#{id}")
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

  def zones
    json.dig('response', 'dns_zones') || []
  end

  def zone_obj
    json.dig('response', 'dns_zone') || json['response']
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

  def create_zone!(name:, user: nil, role: :forward_role, source: :internal_source, enabled: true,
                   label: '', default_ttl: 3600, email: 'dns@example.test',
                   reverse_network_address: nil, reverse_network_prefix: nil)
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: role,
      zone_source: source,
      enabled: enabled,
      label: label,
      default_ttl: default_ttl,
      email: email,
      reverse_network_address: reverse_network_address,
      reverse_network_prefix: reverse_network_prefix
    )
  end

  def create_record!(zone:)
    DnsRecord.create!(
      dns_zone: zone,
      name: 'www',
      record_type: 'A',
      content: '192.0.2.123'
    )
  end

  let!(:zone_a) do
    create_zone!(
      name: 'spec-a.example.test.',
      role: :forward_role,
      source: :internal_source,
      email: 'admin@example.test'
    )
  end

  let!(:zone_b) do
    create_zone!(
      name: 'spec-b.example.test.',
      user: SpecSeed.user,
      role: :forward_role,
      source: :external_source,
      enabled: false,
      email: 'user@example.test'
    )
  end

  let!(:rev_zone) do
    create_zone!(
      name: '2.0.192.in-addr.arpa.',
      role: :reverse_role,
      source: :internal_source,
      email: 'admin@example.test',
      reverse_network_address: '192.0.2.0',
      reverse_network_prefix: 24
    )
  end

  let!(:zone_record) { create_record!(zone: zone_a) }

  describe 'API description' do
    it 'includes dns zone endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dns_zone#index',
        'dns_zone#show',
        'dns_zone#create',
        'dns_zone#update',
        'dns_zone#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists zones owned by the user' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(zones).to be_an(Array)

      ids = zones.map { |row| row['id'] }
      expect(ids).to include(zone_b.id)
      expect(ids).not_to include(zone_a.id)

      row = zones.find { |item| item['id'] == zone_b.id }
      expect(row).to include('id', 'name', 'role', 'source', 'enabled')
      expect(row['name']).to eq(zone_b.name)
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
    end

    it 'allows support to list zones (restricted to own)' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(zones).to be_an(Array)
    end

    it 'allows admins to list all zones' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to include(zone_a.id, zone_b.id, rev_zone.id)
    end

    it 'filters by user when nil' do
      as(SpecSeed.admin) { json_get index_path, dns_zone: { user: nil } }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to contain_exactly(zone_a.id, rev_zone.id)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dns_zone: { limit: 1 } }

      expect_status(200)
      expect(zones.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = DnsZone.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_zone: { from_id: boundary } }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsZone.existing.count)
    end

    it 'filters by role' do
      as(SpecSeed.admin) { json_get index_path, dns_zone: { role: 'reverse_role' } }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to contain_exactly(rev_zone.id)
    end

    it 'filters by source' do
      as(SpecSeed.admin) { json_get index_path, dns_zone: { source: 'external_source' } }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to contain_exactly(zone_b.id)
    end

    it 'filters by enabled' do
      as(SpecSeed.admin) { json_get index_path, dns_zone: { enabled: false } }

      expect_status(200)
      ids = zones.map { |row| row['id'] }
      expect(ids).to contain_exactly(zone_b.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(zone_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their zone' do
      as(SpecSeed.user) { json_get show_path(zone_b.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(zone_obj['id']).to eq(zone_b.id)
      expect(zone_obj['name']).to eq(zone_b.name)
      expect(rid(zone_obj['user'])).to eq(SpecSeed.user.id)
    end

    it 'returns 404 for users accessing other zones' do
      as(SpecSeed.user) { json_get show_path(zone_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any zone' do
      as(SpecSeed.admin) { json_get show_path(zone_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(zone_obj).to include('id', 'name', 'role', 'source', 'enabled', 'default_ttl', 'email')
      expect(zone_obj['id']).to eq(zone_a.id)
      expect(zone_obj['name']).to eq(zone_a.name)
      expect(zone_obj['role']).to eq(zone_a.zone_role)
      expect(zone_obj['source']).to eq(zone_a.zone_source)
    end

    it 'returns 404 for unknown zone' do
      missing = DnsZone.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        name: "spec-create-#{SecureRandom.hex(4)}.example.test.",
        label: 'Spec Zone',
        source: 'internal_source',
        email: 'owner@example.test',
        enabled: true
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, dns_zone: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to create their own zone' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.user) { json_post index_path, dns_zone: payload }
      end.to change(DnsZone, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(zone_obj).to be_a(Hash)
      expect(zone_obj['name']).to eq(payload[:name])

      record = DnsZone.find_by!(name: payload[:name])
      expect(record.user_id).to eq(SpecSeed.user.id)
    end

    it 'returns validation errors for missing name' do
      as(SpecSeed.admin) { json_post index_path, dns_zone: payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for invalid name' do
      as(SpecSeed.admin) do
        json_post index_path, dns_zone: payload.merge(name: 'invalid.example.test')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('name')
    end

    it 'rejects duplicate names' do
      as(SpecSeed.admin) { json_post index_path, dns_zone: payload.merge(name: zone_a.name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('already exists')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(zone_b.id), dns_zone: { label: 'Spec Zone Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for users updating other zones' do
      as(SpecSeed.user) { json_put show_path(zone_a.id), dns_zone: { label: 'Spec Zone Updated' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to update their zone and returns the object' do
      ensure_signer_unlocked!
      new_label = "Spec Zone Updated #{SecureRandom.hex(3)}"

      as(SpecSeed.user) do
        json_put show_path(zone_b.id), dns_zone: {
          label: new_label,
          enabled: true
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(zone_obj).to be_a(Hash)
      expect(zone_obj['label']).to eq(new_label)
      expect(zone_obj['enabled']).to be(true)

      zone_b.reload
      expect(zone_b.label).to eq(new_label)
      expect(zone_b.enabled).to be(true)
    end

    it 'returns validation errors for invalid email' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(zone_a.id), dns_zone: { email: 'invalid-email' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('email')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(zone_b.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for users deleting other zones' do
      as(SpecSeed.user) { json_delete show_path(zone_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to delete their zone' do
      ensure_signer_unlocked!
      zone = create_zone!(
        name: "spec-delete-#{SecureRandom.hex(4)}.example.test.",
        user: SpecSeed.user,
        source: :external_source,
        email: 'user@example.test'
      )

      as(SpecSeed.user) { json_delete show_path(zone.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DnsZone.where(id: zone.id)).to be_empty
    end

    it 'allows admins to delete system zones and removes records' do
      as(SpecSeed.admin) { json_delete show_path(zone_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DnsZone.where(id: zone_a.id)).to be_empty
      expect(DnsRecord.where(id: zone_record.id)).to be_empty
    end

    it 'returns 404 for unknown zone' do
      missing = DnsZone.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
