# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::KnownDevice' do
  before do
    header 'Accept', 'application/json'
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

  def index_path(user_id)
    vpath("/users/#{user_id}/known_devices")
  end

  def show_path(user_id, device_id)
    vpath("/users/#{user_id}/known_devices/#{device_id}")
  end

  def delete_path(user_id, device_id)
    show_path(user_id, device_id)
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def device_list
    json.dig('response', 'known_devices') || []
  end

  def device_obj
    json.dig('response', 'known_device') || json['response']
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_device!(user:, ip:, ua:, token: true, skip_mfa_until: nil)
    device = UserDevice.new(
      user: user,
      client_ip_addr: ip,
      client_ip_ptr: "ptr-#{ip}",
      user_agent: UserAgent.find_or_create!(ua),
      known: true,
      last_seen_at: Time.now,
      skip_multi_factor_auth_until: skip_mfa_until
    )

    if token
      Token.for_new_record!(Time.now + 3600) do |t|
        device.token = t
        device.save!
        device
      end
    else
      device.token = nil
      device.save!
    end

    device
  end

  def create_devices
    {
      user_device_a: create_device!(user: user, ip: '192.0.2.10', ua: 'Spec UA A'),
      user_device_b: create_device!(user: user, ip: '192.0.2.11', ua: 'Spec UA B'),
      user_device_closed: create_device!(user: user, ip: '192.0.2.12', ua: 'Spec UA C', token: false),
      other_device: create_device!(user: other_user, ip: '192.0.2.13', ua: 'Spec UA D')
    }
  end

  def expect_device_fields(row)
    expect(row).to include(
      'id',
      'client_ip_addr',
      'client_ip_ptr',
      'user_agent',
      'created_at',
      'updated_at',
      'last_seen_at'
    )
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to list their own active devices' do
      data = create_devices
      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = device_list.map { |row| row['id'] }
      expect(ids).to include(data[:user_device_a].id, data[:user_device_b].id)
      expect(ids).not_to include(data[:user_device_closed].id)
      expect(ids).not_to include(data[:other_device].id)

      row = device_list.find { |device| device['id'] == data[:user_device_a].id }
      expect(row).not_to be_nil
      expect_device_fields(row)
    end

    it 'denies normal user listing another user devices' do
      create_devices
      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to list any user devices' do
      data = create_devices
      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = device_list.map { |row| row['id'] }
      expect(ids).to include(data[:other_device].id)
    end

    it 'supports limit pagination' do
      create_devices
      as(user) { json_get index_path(user.id), known_device: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      create_devices
      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = device_list.map { |row| row['id'] }
      from_id = ids.min

      as(user) { json_get index_path(user.id), known_device: { from_id: from_id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list.map { |row| row['id'] }).to all(be > from_id)
    end

    it 'rejects negative pagination values' do
      create_devices
      as(user) { json_get index_path(user.id), known_device: { limit: -1, from_id: -1 } }

      expect_status(200)
      expect(json['status']).to be(false)
      keys = response_errors.keys.map(&:to_s)
      expect(keys).to include('limit', 'from_id')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      data = create_devices
      json_get show_path(user.id, data[:user_device_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to show their own active device' do
      data = create_devices
      as(user) { json_get show_path(user.id, data[:user_device_a].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_obj['id']).to eq(data[:user_device_a].id)
      expect_device_fields(device_obj)
    end

    it 'denies access when requesting another user_id' do
      data = create_devices
      as(user) { json_get show_path(other_user.id, data[:other_device].id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'returns 404 when showing another user device id under own user_id' do
      data = create_devices
      as(user) { json_get show_path(user.id, data[:other_device].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for inactive device' do
      data = create_devices
      as(user) { json_get show_path(user.id, data[:user_device_closed].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any user active device' do
      data = create_devices
      as(admin) { json_get show_path(other_user.id, data[:other_device].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_obj['id']).to eq(data[:other_device].id)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      data = create_devices
      json_delete delete_path(user.id, data[:user_device_a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to delete their own active device' do
      data = create_devices
      device = data[:user_device_a]
      old_token_id = device.token_id

      as(user) { json_delete delete_path(user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      device.reload
      expect(device.token_id).to be_nil
      expect(Token.where(id: old_token_id)).to be_empty
      expect(UserDevice.active.where(id: device.id)).to be_empty

      as(user) { json_get show_path(user.id, device.id) }
      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'denies access when deleting under other user_id' do
      data = create_devices
      as(user) { json_delete delete_path(other_user.id, data[:other_device].id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'returns 404 when deleting another user device id under own user_id' do
      data = create_devices
      as(user) { json_delete delete_path(user.id, data[:other_device].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when deleting inactive device' do
      data = create_devices
      as(user) { json_delete delete_path(user.id, data[:user_device_closed].id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete any user device' do
      data = create_devices
      device = data[:other_device]
      old_token_id = device.token_id

      as(admin) { json_delete delete_path(other_user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      device.reload
      expect(device.token_id).to be_nil
      expect(Token.where(id: old_token_id)).to be_empty
      expect(UserDevice.active.where(id: device.id)).to be_empty
    end
  end
end
