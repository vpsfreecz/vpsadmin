# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnssecRecord' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.support
  end

  def index_path
    vpath('/dnssec_records')
  end

  def show_path(id)
    vpath("/dnssec_records/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def records
    json.dig('response', 'dnssec_records') || []
  end

  def record_obj
    json.dig('response', 'dnssec_record') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_zone!(name:, user:, source: :internal_source)
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: :forward_role,
      zone_source: source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: 'dns@example.test'
    )
  end

  def create_dnssec_record!(zone:, keyid:)
    DnssecRecord.create!(
      dns_zone: zone,
      keyid: keyid,
      dnskey_algorithm: 13,
      dnskey_pubkey: "PUBKEY-#{SecureRandom.hex(8)}",
      ds_algorithm: 13,
      ds_digest_type: 2,
      ds_digest: "DIGEST-#{SecureRandom.hex(16)}"
    )
  end

  let!(:seed_zones) do
    {
      user: create_zone!(name: 'spec-user.example.test.', user: SpecSeed.user),
      other: create_zone!(name: 'spec-other.example.test.', user: SpecSeed.other_user),
      support: create_zone!(name: 'spec-support.example.test.', user: SpecSeed.support),
      system: create_zone!(name: 'spec-system.example.test.', user: nil)
    }
  end

  let!(:seed_records) do
    {
      user_a: create_dnssec_record!(zone: seed_zones[:user], keyid: 101),
      user_b: create_dnssec_record!(zone: seed_zones[:user], keyid: 102),
      other: create_dnssec_record!(zone: seed_zones[:other], keyid: 201),
      support: create_dnssec_record!(zone: seed_zones[:support], keyid: 301),
      system: create_dnssec_record!(zone: seed_zones[:system], keyid: 401)
    }
  end

  def zone_user
    seed_zones.fetch(:user)
  end

  def zone_other
    seed_zones.fetch(:other)
  end

  def zone_support
    seed_zones.fetch(:support)
  end

  def zone_system
    seed_zones.fetch(:system)
  end

  def rec_user_a
    seed_records.fetch(:user_a)
  end

  def rec_user_b
    seed_records.fetch(:user_b)
  end

  def rec_other
    seed_records.fetch(:other)
  end

  def rec_support
    seed_records.fetch(:support)
  end

  def rec_system
    seed_records.fetch(:system)
  end

  describe 'API description' do
    it 'includes dnssec record endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'dnssec_record#index',
        'dnssec_record#show'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists records owned by the user' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(records).to be_an(Array)

      ids = records.map { |row| row['id'] }
      expect(ids).to include(rec_user_a.id, rec_user_b.id)
      expect(ids).not_to include(rec_other.id, rec_support.id, rec_system.id)

      row = records.find { |item| item['id'] == rec_user_a.id }
      expect(row).to include(
        'id',
        'dns_zone',
        'keyid',
        'dnskey_algorithm',
        'dnskey_pubkey',
        'ds_algorithm',
        'ds_digest_type',
        'ds_digest',
        'created_at',
        'updated_at'
      )
      expect(rid(row['dns_zone'])).to eq(zone_user.id)
    end

    it 'lists records for support (restricted to own zones)' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to include(rec_support.id)
      expect(ids).not_to include(rec_user_a.id, rec_other.id, rec_system.id)
    end

    it 'lists all records for admin' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to include(rec_user_a.id, rec_user_b.id, rec_other.id, rec_support.id, rec_system.id)
    end

    it 'filters by dns_zone for admin' do
      as(SpecSeed.admin) { json_get index_path, dnssec_record: { dns_zone: zone_user.id } }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to contain_exactly(rec_user_a.id, rec_user_b.id)
    end

    it 'filters by dns_zone for user' do
      as(SpecSeed.user) { json_get index_path, dnssec_record: { dns_zone: zone_user.id } }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to contain_exactly(rec_user_a.id, rec_user_b.id)
    end

    it 'returns empty list when user filters by other zone' do
      as(SpecSeed.user) { json_get index_path, dnssec_record: { dns_zone: zone_other.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(records).to eq([])
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dnssec_record: { limit: 1 } }

      expect_status(200)
      expect(records.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = DnssecRecord.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dnssec_record: { from_id: boundary } }

      expect_status(200)
      ids = records.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnssecRecord.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(rec_user_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a record for the owner' do
      as(SpecSeed.user) { json_get show_path(rec_user_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(record_obj['id']).to eq(rec_user_a.id)
      expect(rid(record_obj['dns_zone'])).to eq(zone_user.id)
      expect(record_obj['keyid']).to eq(rec_user_a.keyid)
      expect(record_obj['dnskey_algorithm']).to eq(rec_user_a.dnskey_algorithm)
      expect(record_obj['dnskey_pubkey']).to eq(rec_user_a.dnskey_pubkey)
      expect(record_obj['ds_algorithm']).to eq(rec_user_a.ds_algorithm)
      expect(record_obj['ds_digest_type']).to eq(rec_user_a.ds_digest_type)
      expect(record_obj['ds_digest']).to eq(rec_user_a.ds_digest)
    end

    it 'returns 404 for records outside restrictions' do
      as(SpecSeed.user) { json_get show_path(rec_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for system records outside restrictions' do
      as(SpecSeed.user) { json_get show_path(rec_system.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any record' do
      as(SpecSeed.admin) { json_get show_path(rec_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'allows admin to show system record' do
      as(SpecSeed.admin) { json_get show_path(rec_system.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown id' do
      missing = DnssecRecord.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
