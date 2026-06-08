# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::WebuiUserSetting', requires_plugins: :webui do
  before do
    header 'Accept', 'application/json'
    WebuiUserSetting.delete_all
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  def index_path
    vpath('/webui_user_settings')
  end

  def setting_path(namespace, key)
    vpath("/webui_user_settings/#{namespace}/#{key}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
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

  def webui_user_settings
    json.dig('response', 'webui_user_settings') || []
  end

  def webui_user_setting
    json.dig('response', 'webui_user_setting') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    let!(:own_tip) do
      WebuiUserSetting.set!(
        user: user,
        namespace: 'tips',
        key: 'time_zone',
        value: { 'dismissed' => true }
      )
    end

    let!(:own_ui) do
      WebuiUserSetting.set!(
        user: user,
        namespace: 'ui',
        key: 'collapsed_sidebar',
        value: true
      )
    end

    before do
      WebuiUserSetting.set!(
        user: other_user,
        namespace: 'tips',
        key: 'time_zone',
        value: { 'dismissed' => true }
      )
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only current user settings' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(webui_user_settings.map { |row| row['id'] }).to contain_exactly(
        own_tip.id,
        own_ui.id
      )
    end

    it 'filters current user settings by namespace and key' do
      as(user) do
        json_get index_path, webui_user_setting: {
          namespace: 'tips',
          key: 'time_zone'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(webui_user_settings.map { |row| row['id'] }).to eq([own_tip.id])
    end
  end

  describe 'Show' do
    before do
      WebuiUserSetting.set!(
        user: user,
        namespace: 'tips',
        key: 'time_zone',
        value: { 'dismissed' => true }
      )
    end

    it 'rejects unauthenticated access' do
      json_get setting_path('tips', 'time_zone')

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a current user setting by namespace and key' do
      as(user) { json_get setting_path('tips', 'time_zone') }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(webui_user_setting).to include(
        'namespace' => 'tips',
        'key' => 'time_zone',
        'value' => { 'dismissed' => true }
      )
    end

    it 'does not show another user setting' do
      as(other_user) { json_get setting_path('tips', 'time_zone') }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Set' do
    it 'rejects unauthenticated access' do
      json_put setting_path('tips', 'time_zone'), webui_user_setting: {
        value: { dismissed: true }
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'creates and updates a current user setting' do
      as(user) do
        json_put setting_path('tips', 'time_zone'), webui_user_setting: {
          value: { dismissed: true }
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(webui_user_setting).to include(
        'namespace' => 'tips',
        'key' => 'time_zone',
        'value' => { 'dismissed' => true }
      )
      expect(WebuiUserSetting.where(user: user).count).to eq(1)

      as(user) do
        json_put setting_path('tips', 'time_zone'), webui_user_setting: {
          value: { dismissed: false, action: 'use_browser_time_zone' }
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(WebuiUserSetting.where(user: user).count).to eq(1)
      expect(webui_user_setting['value']).to eq(
        'dismissed' => false,
        'action' => 'use_browser_time_zone'
      )
    end

    it 'rejects unregistered namespaces' do
      as(user) do
        json_put setting_path('unknown', 'time_zone'), webui_user_setting: {
          value: { dismissed: true }
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('namespace')
    end

    it 'rejects oversized values' do
      as(user) do
        json_put setting_path('tips', 'large'), webui_user_setting: {
          value: { data: 'x' * (WebuiUserSetting::MAX_VALUE_BYTES + 1) }
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('value')
    end

    it 'limits the number of stored keys per user' do
      WebuiUserSetting::MAX_SETTINGS_PER_USER.times do |i|
        WebuiUserSetting.set!(
          user: user,
          namespace: 'tips',
          key: "key_#{i}",
          value: true
        )
      end

      as(user) do
        json_put setting_path('tips', 'too_many'), webui_user_setting: {
          value: true
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('base')
    end

    it 'limits the total serialized value size per user' do
      payload = 'x' * (WebuiUserSetting::MAX_VALUE_BYTES - 20)

      8.times do |i|
        WebuiUserSetting.set!(
          user: user,
          namespace: 'tips',
          key: "key_#{i}",
          value: { 'data' => payload }
        )
      end

      as(user) do
        json_put setting_path('tips', 'too_large_total'), webui_user_setting: {
          value: { data: 'x' * 1000 }
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('base')
    end
  end

  describe 'Delete' do
    before do
      WebuiUserSetting.set!(
        user: user,
        namespace: 'tips',
        key: 'time_zone',
        value: { 'dismissed' => true }
      )
    end

    it 'rejects unauthenticated access' do
      json_delete setting_path('tips', 'time_zone')

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'deletes a current user setting' do
      as(user) { json_delete setting_path('tips', 'time_zone') }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(WebuiUserSetting.find_by(user: user, namespace: 'tips', key: 'time_zone')).to be_nil
    end

    it 'does not delete another user setting' do
      as(other_user) { json_delete setting_path('tips', 'time_zone') }

      expect_status(404)
      expect(json['status']).to be(false)
      expect(WebuiUserSetting.find_by(user: user, namespace: 'tips', key: 'time_zone')).not_to be_nil
    end
  end
end
