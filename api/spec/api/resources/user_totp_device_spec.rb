# frozen_string_literal: true

require 'rotp'
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User::TotpDevice' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }

  def index_path(user_id)
    vpath("/users/#{user_id}/totp_devices")
  end

  def show_path(user_id, device_id)
    vpath("/users/#{user_id}/totp_devices/#{device_id}")
  end

  def confirm_path(user_id, device_id)
    vpath("/users/#{user_id}/totp_devices/#{device_id}/confirm")
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
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def device_list
    json.dig('response', 'totp_devices') || []
  end

  def device_obj
    json.dig('response', 'totp_device') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_device!(user:, label: 'Spec device', confirmed: false, enabled: false, secret: nil)
    UserTotpDevice.create!(
      user: user,
      label: label,
      confirmed: confirmed,
      enabled: enabled,
      secret: secret || ROTP::Base32.random
    )
  end

  def create_devices
    {
      user_unconfirmed: create_device!(user: user, label: 'Spec A', confirmed: false, enabled: false),
      user_confirmed_enabled: create_device!(user: user, label: 'Spec B', confirmed: true, enabled: true),
      user_confirmed_disabled: create_device!(user: user, label: 'Spec C', confirmed: true, enabled: false),
      other_device: create_device!(user: other_user, label: 'Other', confirmed: true, enabled: true)
    }
  end

  def expect_device_fields(row)
    expect(row).to include(
      'id',
      'label',
      'confirmed',
      'enabled',
      'last_use_at',
      'use_count',
      'created_at',
      'updated_at'
    )
  end

  describe 'API description' do
    it 'includes user.totp_device endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user.totp_device#index',
        'user.totp_device#show',
        'user.totp_device#create',
        'user.totp_device#confirm',
        'user.totp_device#update',
        'user.totp_device#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists devices for the authenticated user' do
      data = create_devices

      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = device_list.map { |row| row['id'] }
      expect(ids).to include(
        data[:user_unconfirmed].id,
        data[:user_confirmed_enabled].id,
        data[:user_confirmed_disabled].id
      )
      expect(ids).not_to include(data[:other_device].id)
    end

    it 'denies listing devices for another user' do
      create_devices

      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to list devices for any user' do
      data = create_devices

      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = device_list.map { |row| row['id'] }
      expect(ids).to include(data[:other_device].id)
    end

    it 'supports filtering by confirmed' do
      create_devices

      as(user) { json_get index_path(user.id), totp_device: { confirmed: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list).not_to be_empty
      expect(device_list.map { |row| row['confirmed'] }).to all(be(true))
    end

    it 'supports filtering by enabled' do
      create_devices

      as(user) { json_get index_path(user.id), totp_device: { enabled: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list).not_to be_empty
      expect(device_list.map { |row| row['enabled'] }).to all(be(true))
    end

    it 'supports limit pagination' do
      create_devices

      as(user) { json_get index_path(user.id), totp_device: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      create_devices

      boundary = UserTotpDevice.order(:id).first.id

      as(admin) { json_get index_path(user.id), totp_device: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_list).not_to be_empty
      expect(device_list.map { |row| row['id'] }).to all(be > boundary)
    end

    it 'supports meta count' do
      create_devices
      count = UserTotpDevice.where(user_id: user.id).count

      as(admin) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      device = create_device!(user: user)

      json_get show_path(user.id, device.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own device' do
      device = create_device!(user: user, confirmed: true, enabled: true)

      as(user) { json_get show_path(user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_obj['id']).to eq(device.id)
      expect_device_fields(device_obj)
      expect(device_obj.keys).not_to include('secret', 'recovery_code')
    end

    it 'denies access when requesting another user device by user_id' do
      device = create_device!(user: other_user)

      as(user) { json_get show_path(other_user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'returns 404 for missing device id' do
      missing = UserTotpDevice.maximum(:id).to_i + 100

      as(user) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any device' do
      device = create_device!(user: other_user)

      as(admin) { json_get show_path(other_user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(device_obj['id']).to eq(device.id)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path(user.id), totp_device: { label: 'Phone' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'creates device for self' do
      as(user) { json_post index_path(user.id), totp_device: { label: 'Phone' } }

      expect_status(200)
      expect(json['status']).to be(true)

      expect_device_fields(device_obj)
      expect(device_obj['secret']).to be_a(String)
      expect(device_obj['provisioning_uri']).to be_a(String)

      record = UserTotpDevice.find_by!(user_id: user.id, label: 'Phone')
      expect(record.confirmed).to be(false)
      expect(record.enabled).to be(false)
      expect(record.secret).to eq(device_obj['secret'])
    end

    it 'returns validation error for missing label' do
      as(user) { json_post index_path(user.id), totp_device: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'denies creating device for other user' do
      as(user) { json_post index_path(other_user.id), totp_device: { label: 'Other' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to create device for other user' do
      as(admin) { json_post index_path(other_user.id), totp_device: { label: 'Admin created' } }

      expect_status(200)
      expect(json['status']).to be(true)
      record = UserTotpDevice.find_by!(user_id: other_user.id, label: 'Admin created')
      expect(record.user_id).to eq(other_user.id)
    end
  end

  describe 'Confirm' do
    it 'rejects unauthenticated access' do
      device = create_device!(user: user)

      json_post confirm_path(user.id, device.id), totp_device: { code: '000000' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'confirms an unconfirmed device' do
      device = create_device!(user: user, confirmed: false, enabled: false)
      t = Time.at(1_700_000_000)

      allow(Time).to receive(:now).and_return(t)
      code = device.totp.at(t)

      as(user) { json_post confirm_path(user.id, device.id), totp_device: { code: code } }

      expect_status(200)
      expect(json['status']).to be(true)

      recovery_code =
        json.dig('response', 'totp_device', 'recovery_code') ||
        json.dig('response', 'recovery_code') ||
        json['recovery_code']
      recovery_code = json['response'] if recovery_code.nil? && json['response'].is_a?(String)
      expect(recovery_code).to be_a(String)
      expect(recovery_code.length).to eq(40)

      device.reload
      expect(device.confirmed).to be(true)
      expect(device.enabled).to be(true)
      expect(device.recovery_code).not_to be_nil

      user.reload
      expect(user.enable_multi_factor_auth).to be(true)
    end

    it 'rejects invalid code' do
      device = create_device!(user: user, confirmed: false, enabled: false)
      t = Time.at(1_700_000_000)

      allow(Time).to receive(:now).and_return(t)
      code = device.totp.at(t)
      invalid = (code.to_i + 1) % 1_000_000
      invalid_code = invalid.to_s.rjust(6, '0')

      as(user) { json_post confirm_path(user.id, device.id), totp_device: { code: invalid_code } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('invalid totp code')

      device.reload
      expect(device.confirmed).to be(false)
      expect(device.enabled).to be(false)
    end

    it 'rejects confirming an already confirmed device' do
      device = create_device!(user: user, confirmed: true, enabled: true)

      as(user) { json_post confirm_path(user.id, device.id), totp_device: { code: '000000' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already confirmed')
    end

    it 'denies confirming device for another user' do
      device = create_device!(user: other_user, confirmed: false, enabled: false)

      as(user) { json_post confirm_path(other_user.id, device.id), totp_device: { code: '000000' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      device = create_device!(user: user)

      json_put show_path(user.id, device.id), totp_device: { label: 'New label' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'updates label' do
      device = create_device!(user: user, label: 'Old')

      as(user) { json_put show_path(user.id, device.id), totp_device: { label: 'New label' } }

      expect_status(200)
      expect(json['status']).to be(true)

      device.reload
      expect(device.label).to eq('New label')
    end

    it 'returns error on empty payload' do
      device = create_device!(user: user)

      as(user) { json_put show_path(user.id, device.id), totp_device: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('nothing to do')
    end

    it 'cannot enable an unconfirmed device' do
      device = create_device!(user: user, confirmed: false, enabled: false)

      as(user) { json_put show_path(user.id, device.id), totp_device: { enabled: true } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('unconfirmed device cannot be enabled')
    end

    it 'can enable a confirmed device' do
      device = create_device!(user: user, confirmed: true, enabled: false)
      user.update!(enable_multi_factor_auth: false)

      as(user) { json_put show_path(user.id, device.id), totp_device: { enabled: true } }

      expect_status(200)
      expect(json['status']).to be(true)

      device.reload
      expect(device.enabled).to be(true)

      user.reload
      expect(user.enable_multi_factor_auth).to be(true)
    end

    it 'can disable a device' do
      device = create_device!(user: user, confirmed: true, enabled: true)

      as(admin) { json_put show_path(user.id, device.id), totp_device: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)

      device.reload
      expect(device.enabled).to be(false)
    end

    it 'denies updating another user device by user_id' do
      device = create_device!(user: other_user)

      as(user) { json_put show_path(other_user.id, device.id), totp_device: { label: 'Nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'returns 404 for missing device id' do
      missing = UserTotpDevice.maximum(:id).to_i + 100

      as(user) { json_put show_path(user.id, missing), totp_device: { label: 'Nope' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      device = create_device!(user: user)

      json_delete show_path(user.id, device.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'deletes own device' do
      device = create_device!(user: user)

      as(user) { json_delete show_path(user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserTotpDevice.exists?(device.id)).to be(false)
    end

    it 'denies deleting another user device by user_id' do
      device = create_device!(user: other_user)

      as(user) { json_delete show_path(other_user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to delete other user device' do
      device = create_device!(user: other_user)

      as(admin) { json_delete show_path(other_user.id, device.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserTotpDevice.exists?(device.id)).to be(false)
    end

    it 'returns 404 for missing device id' do
      missing = UserTotpDevice.maximum(:id).to_i + 100

      as(user) { json_delete show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
