# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User::WebauthnCredential' do
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
    vpath("/users/#{user_id}/webauthn_credentials")
  end

  def show_path(user_id, cred_id)
    vpath("/users/#{user_id}/webauthn_credentials/#{cred_id}")
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

  def creds
    json.dig('response', 'webauthn_credentials') || []
  end

  def cred
    json.dig('response', 'webauthn_credential') || {}
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_cred!(owner:, label:, enabled: true)
    WebauthnCredential.create!(
      user: owner,
      label: label,
      enabled: enabled,
      external_id: SecureRandom.hex(16),
      public_key: 'spec-public-key',
      sign_count: 0
    )
  end

  def create_creds
    {
      user_enabled: create_cred!(owner: user, label: 'Spec Enabled', enabled: true),
      user_disabled: create_cred!(owner: user, label: 'Spec Disabled', enabled: false),
      other_enabled: create_cred!(owner: other_user, label: 'Other Enabled', enabled: true)
    }
  end

  def expect_credential_fields(row)
    expect(row).to include(
      'id',
      'label',
      'enabled',
      'use_count',
      'last_use_at',
      'created_at',
      'updated_at'
    )
  end

  describe 'API description' do
    it 'includes user.webauthn_credential endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user.webauthn_credential#index',
        'user.webauthn_credential#show',
        'user.webauthn_credential#update',
        'user.webauthn_credential#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists credentials for the owning user' do
      data = create_creds

      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = creds.map { |row| row['id'] }
      expect(ids).to include(data[:user_enabled].id, data[:user_disabled].id)
      expect(ids).not_to include(data[:other_enabled].id)

      row = creds.find { |item| item['id'] == data[:user_enabled].id }
      expect_credential_fields(row)
      expect(row.keys).not_to include('external_id', 'public_key', 'sign_count')
    end

    it 'allows admin to list other user credentials' do
      data = create_creds

      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(creds.map { |row| row['id'] }).to include(data[:other_enabled].id)
    end

    it 'denies listing credentials for another user (non-admin)' do
      create_creds

      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'filters by enabled' do
      data = create_creds

      as(user) { json_get index_path(user.id), webauthn_credential: { enabled: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(creds.map { |row| row['id'] }).to include(data[:user_enabled].id)
      expect(creds.map { |row| row['id'] }).not_to include(data[:user_disabled].id)
    end

    it 'supports limit pagination' do
      create_creds

      as(user) { json_get index_path(user.id), webauthn_credential: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(creds.length).to eq(1)
    end

    it 'supports from_id pagination' do
      data = create_creds
      boundary = data[:user_enabled].id

      as(user) { json_get index_path(user.id), webauthn_credential: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(creds).not_to be_empty
      expect(creds.map { |row| row['id'] }).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      create_creds
      count = WebauthnCredential.where(user: user).count

      as(user) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      record = create_cred!(owner: user, label: 'Spec')

      json_get show_path(user.id, record.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own credential' do
      record = create_cred!(owner: user, label: 'Spec')

      as(user) { json_get show_path(user.id, record.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cred['id']).to eq(record.id)
      expect(cred['label']).to eq(record.label)
      expect(cred['enabled']).to eq(record.enabled)
      expect_credential_fields(cred)
      expect(cred.keys).not_to include('external_id', 'public_key', 'sign_count')
    end

    it 'allows admin to show other user credentials' do
      record = create_cred!(owner: other_user, label: 'Other')

      as(admin) { json_get show_path(other_user.id, record.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cred['id']).to eq(record.id)
    end

    it 'denies showing credentials for another user (non-admin)' do
      record = create_cred!(owner: other_user, label: 'Other')

      as(user) { json_get show_path(other_user.id, record.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'returns 404 for missing credential id' do
      missing = WebauthnCredential.maximum(:id).to_i + 100

      as(user) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      record = create_cred!(owner: user, label: 'Spec')

      json_put show_path(user.id, record.id), webauthn_credential: { label: 'New Label' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'updates label' do
      record = create_cred!(owner: user, label: 'Old Label')

      as(user) { json_put show_path(user.id, record.id), webauthn_credential: { label: 'New Label' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(cred['label']).to eq('New Label')

      record.reload
      expect(record.label).to eq('New Label')
    end

    it 'disables a credential' do
      record = create_cred!(owner: user, label: 'Spec', enabled: true)

      as(user) { json_put show_path(user.id, record.id), webauthn_credential: { enabled: false } }

      expect_status(200)
      expect(json['status']).to be(true)

      record.reload
      expect(record.enabled).to be(false)
    end

    it 'rejects empty payload' do
      record = create_cred!(owner: user, label: 'Spec')

      as(user) { json_put show_path(user.id, record.id), webauthn_credential: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('nothing to do')
    end

    it 'returns validation error for short label' do
      record = create_cred!(owner: user, label: 'Spec')

      as(user) { json_put show_path(user.id, record.id), webauthn_credential: { label: 'x' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'denies updating credentials for another user (non-admin)' do
      record = create_cred!(owner: other_user, label: 'Other')

      as(user) { json_put show_path(other_user.id, record.id), webauthn_credential: { label: 'Nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to update other user credential' do
      record = create_cred!(owner: other_user, label: 'Other')

      as(admin) { json_put show_path(other_user.id, record.id), webauthn_credential: { label: 'Admin Updated' } }

      expect_status(200)
      expect(json['status']).to be(true)

      record.reload
      expect(record.label).to eq('Admin Updated')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      record = create_cred!(owner: user, label: 'Spec')

      json_delete show_path(user.id, record.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'deletes own credential' do
      record = create_cred!(owner: user, label: 'Spec', enabled: false)

      expect { as(user) { json_delete show_path(user.id, record.id) } }
        .to change(WebauthnCredential, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'denies deleting credentials for another user (non-admin)' do
      record = create_cred!(owner: other_user, label: 'Other')

      as(user) { json_delete show_path(other_user.id, record.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'allows admin to delete other user credential' do
      record = create_cred!(owner: other_user, label: 'Other')

      expect { as(admin) { json_delete show_path(other_user.id, record.id) } }
        .to change(WebauthnCredential, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for missing credential id' do
      missing = WebauthnCredential.maximum(:id).to_i + 100

      as(user) { json_delete show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
