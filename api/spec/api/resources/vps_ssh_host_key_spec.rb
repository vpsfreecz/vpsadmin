# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::VPS::SshHostKey' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.node
    fixtures
  end

  let(:fixtures) do
    now = Time.utc(2024, 1, 1, 12, 0, 0)
    user_vps = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    user_vps2 = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps-2')
    other_vps = create_vps_row!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-other-vps')

    key_rsa = create_key!(
      vps: user_vps,
      bits: 4096,
      algorithm: 'rsa',
      fingerprint: 'SHA256:spec-rsa',
      created_at: now - 120
    )
    key_ed = create_key!(
      vps: user_vps,
      bits: 256,
      algorithm: 'ed25519',
      fingerprint: 'SHA256:spec-ed',
      created_at: now - 60
    )
    key_other_vps_same_user = create_key!(
      vps: user_vps2,
      bits: 2048,
      algorithm: 'ecdsa',
      fingerprint: 'SHA256:spec-ecdsa',
      created_at: now - 30
    )
    key_other_user = create_key!(
      vps: other_vps,
      bits: 2048,
      algorithm: 'rsa',
      fingerprint: 'SHA256:spec-other',
      created_at: now - 90
    )

    {
      user_vps: user_vps,
      user_vps2: user_vps2,
      other_vps: other_vps,
      key_rsa: key_rsa,
      key_ed: key_ed,
      key_other_vps_same_user: key_other_vps_same_user,
      key_other_user: key_other_user
    }
  end

  def user_vps
    fixtures.fetch(:user_vps)
  end

  def user_vps2
    fixtures.fetch(:user_vps2)
  end

  def other_vps
    fixtures.fetch(:other_vps)
  end

  def key_rsa
    fixtures.fetch(:key_rsa)
  end

  def key_ed
    fixtures.fetch(:key_ed)
  end

  def key_other_vps_same_user
    fixtures.fetch(:key_other_vps_same_user)
  end

  def key_other_user
    fixtures.fetch(:key_other_user)
  end

  def create_vps_row!(user:, node:, hostname:)
    vps = Vps.new(
      user_id: user.id,
      node_id: node.id,
      hostname: hostname,
      os_template_id: 1
    )

    vps.object_state =
      if Vps.respond_to?(:object_states) && Vps.object_states[:active]
        Vps.object_states[:active]
      else
        0
      end

    vps.save!(validate: false)
    vps
  end

  def create_key!(vps:, bits:, algorithm:, fingerprint:, created_at:)
    VpsSshHostKey.create!(
      vps: vps,
      bits: bits,
      algorithm: algorithm,
      fingerprint: fingerprint,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def index_path(vps_id)
    vpath("/vpses/#{vps_id}/ssh_host_keys")
  end

  def show_path(vps_id, key_id)
    vpath("/vpses/#{vps_id}/ssh_host_keys/#{key_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def key_list
    json.dig('response', 'ssh_host_keys') || json.dig('response', 'vps_ssh_host_keys') || []
  end

  def key_obj
    json.dig('response', 'ssh_host_key') || json.dig('response', 'vps_ssh_host_key') || json['response']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user_vps.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to list keys for own VPS' do
      as(SpecSeed.user) { json_get index_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_list).to be_a(Array)

      ids = key_list.map { |row| row['id'] }
      expect(ids).to include(key_rsa.id, key_ed.id)

      row = key_list.find { |key| key['id'] == key_rsa.id }
      expect(row.keys).to include('id', 'bits', 'fingerprint', 'algorithm', 'created_at', 'updated_at')
    end

    it 'hides other users VPS from normal users' do
      as(SpecSeed.user) { json_get index_path(other_vps.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list keys for any VPS' do
      as(SpecSeed.admin) { json_get index_path(other_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = key_list.map { |row| row['id'] }
      expect(ids).to include(key_other_user.id)
    end

    it 'filters by algorithm' do
      as(SpecSeed.user) { json_get index_path(user_vps.id), ssh_host_key: { algorithm: 'rsa' } }

      expect_status(200)
      ids = key_list.map { |row| row['id'] }
      expect(ids).to include(key_rsa.id)
      expect(ids).not_to include(key_ed.id)
    end

    it 'returns empty list for unmatched algorithm' do
      as(SpecSeed.user) { json_get index_path(user_vps.id), ssh_host_key: { algorithm: 'nope' } }

      expect_status(200)
      expect(key_list).to be_empty
    end

    it 'orders keys by created_at desc' do
      as(SpecSeed.user) { json_get index_path(user_vps.id) }

      expect_status(200)
      ids = key_list.map { |row| row['id'] }
      expect(ids).to eq([key_ed.id, key_rsa.id])
    end

    it 'supports pagination with limit' do
      as(SpecSeed.admin) { json_get index_path(user_vps.id), ssh_host_key: { limit: 1 } }

      expect_status(200)
      expect(key_list.length).to eq(1)
    end

    it 'supports pagination with from_id' do
      boundary = VpsSshHostKey.where(vps_id: user_vps.id).order(:id).first.id
      as(SpecSeed.admin) { json_get index_path(user_vps.id), ssh_host_key: { from_id: boundary } }

      expect_status(200)
      ids = key_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count in meta when requested' do
      as(SpecSeed.admin) { json_get index_path(user_vps.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count'))
        .to eq(VpsSshHostKey.where(vps_id: user_vps.id).count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_vps.id, key_rsa.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show key for own VPS' do
      as(SpecSeed.user) { json_get show_path(user_vps.id, key_rsa.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_obj['id']).to eq(key_rsa.id)
      expect(key_obj['bits']).to eq(key_rsa.bits)
      expect(key_obj['fingerprint']).to eq(key_rsa.fingerprint)
      expect(key_obj['algorithm']).to eq(key_rsa.algorithm)
    end

    it 'hides other users keys from normal users' do
      as(SpecSeed.user) { json_get show_path(other_vps.id, key_other_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when key does not belong to VPS' do
      as(SpecSeed.user) { json_get show_path(user_vps.id, key_other_vps_same_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any key' do
      as(SpecSeed.admin) { json_get show_path(other_vps.id, key_other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_obj['id']).to eq(key_other_user.id)
    end

    it 'returns 404 for unknown key' do
      missing = VpsSshHostKey.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(user_vps.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
