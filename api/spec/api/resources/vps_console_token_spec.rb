# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::VPS::ConsoleToken' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.node
    fixtures
  end

  let(:fixtures) do
    vps_user = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    vps_other = create_vps_row!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-other-vps')

    {
      vps_user: vps_user,
      vps_other: vps_other
    }
  end

  def vps_user
    fixtures.fetch(:vps_user)
  end

  def vps_other
    fixtures.fetch(:vps_other)
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

  def console_token_path(vps_id)
    vpath("/vpses/#{vps_id}/console_token")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload = {})
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

  def console_token
    json.dig('response', 'console_token') || json['response']
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    msg = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), msg
  end

  describe 'API description' do
    it 'includes vps.console_token endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'vps.console_token#create',
        'vps.console_token#show',
        'vps.console_token#delete'
      )
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post console_token_path(vps_user.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create token for own VPS' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      token = console_token['token']
      expect(token).to be_a(String)
      expect(token.length).to eq(100)
      expect(console_token['expiration']).not_to be_nil

      record = VpsConsole.find_for(vps_user, SpecSeed.user)
      expect(record).not_to be_nil
      expect(record.vps_id).to eq(vps_user.id)
      expect(record.user_id).to eq(SpecSeed.user.id)
      expect(record.token).to eq(token)
      expect(record.expiration).to be > Time.now
    end

    it 'returns same token while valid' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      first_token = console_token['token']

      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      expect(console_token['token']).to eq(first_token)
      active_count = VpsConsole.where(vps: vps_user, user: SpecSeed.user).where.not(token: nil).count
      expect(active_count).to eq(1)
    end

    it 'creates new token when previous expired' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      old_token = console_token['token']
      record = VpsConsole.find_for(vps_user, SpecSeed.user)
      record.update!(expiration: Time.now - 60)

      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      expect(console_token['token']).not_to eq(old_token)
      count = VpsConsole.where(vps: vps_user, user: SpecSeed.user).count
      expect(count).to be >= 2
    end

    it 'hides other user VPSes' do
      as(SpecSeed.user) { json_post console_token_path(vps_other.id), {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'blocks non-admin during maintenance' do
      vps_user.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec maintenance'
      )

      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(423)
      expect(json['status']).to be(false)
      expect(response_message).to include('Resource is under maintenance: spec maintenance')
    end

    it 'allows admin during maintenance' do
      vps_user.update!(
        maintenance_lock: MaintenanceLock.maintain_lock(:lock),
        maintenance_lock_reason: 'spec maintenance'
      )

      as(SpecSeed.admin) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get console_token_path(vps_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when no valid token exists' do
      as(SpecSeed.user) { json_get console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns token after create' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      created_token = console_token['token']

      as(SpecSeed.user) { json_get console_token_path(vps_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(console_token['token']).to eq(created_token)
    end

    it 'treats expired token as missing' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      record = VpsConsole.find_for(vps_user, SpecSeed.user)
      record.update!(expiration: Time.now - 60)

      as(SpecSeed.user) { json_get console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'hides other user VPS tokens' do
      as(SpecSeed.other_user) { json_post console_token_path(vps_other.id), {} }

      expect_status(200)

      as(SpecSeed.user) { json_get console_token_path(vps_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'scopes tokens to requesting user' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      user_token = console_token['token']

      as(SpecSeed.admin) { json_get console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(SpecSeed.admin) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)
      admin_token = console_token['token']
      expect(admin_token).not_to eq(user_token)

      as(SpecSeed.admin) { json_get console_token_path(vps_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(console_token['token']).to eq(admin_token)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete console_token_path(vps_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when deleting without a valid token' do
      as(SpecSeed.user) { json_delete console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'revokes token' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)

      as(SpecSeed.user) { json_delete console_token_path(vps_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      record = VpsConsole.where(vps: vps_user, user: SpecSeed.user).order(id: :desc).first
      expect(record).not_to be_nil
      expect(record.token).to be_nil
      expect(VpsConsole.find_for(vps_user, SpecSeed.user)).to be_nil
    end

    it 'returns 404 after delete on show' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)

      as(SpecSeed.user) { json_delete console_token_path(vps_user.id) }

      expect_status(200)

      as(SpecSeed.user) { json_get console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'hides other user VPS tokens' do
      as(SpecSeed.user) { json_delete console_token_path(vps_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'does not let admin delete another user token' do
      as(SpecSeed.user) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)

      as(SpecSeed.admin) { json_delete console_token_path(vps_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)

      as(SpecSeed.admin) { json_post console_token_path(vps_user.id), {} }

      expect_status(200)

      as(SpecSeed.admin) { json_delete console_token_path(vps_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end
end
