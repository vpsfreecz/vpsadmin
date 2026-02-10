# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Oauth2Client' do
  before do
    header 'Accept', 'application/json'
  end

  let(:users) do
    {
      user: SpecSeed.user,
      admin: SpecSeed.admin
    }
  end

  let!(:clients) do
    {
      primary: create_client(
        name: 'Spec Client A',
        client_id: 'spec-client-a',
        redirect_uri: 'https://example.invalid/callback-a',
        secret: 'spec-secret-a'
      ),
      secondary: create_client(
        name: 'Spec Client B',
        client_id: 'spec-client-b',
        redirect_uri: 'https://example.invalid/callback-b',
        secret: 'spec-secret-b'
      )
    }
  end

  def create_client(name:, client_id:, redirect_uri:, secret:)
    client = Oauth2Client.new(
      name:,
      client_id:,
      redirect_uri:
    )
    client.set_secret(secret)
    client.save!
    client
  end

  def user
    users.fetch(:user)
  end

  def admin
    users.fetch(:admin)
  end

  def primary_client
    clients.fetch(:primary)
  end

  def secondary_client
    clients.fetch(:secondary)
  end

  def index_path
    vpath('/oauth2_clients')
  end

  def show_path(id)
    vpath("/oauth2_clients/#{id}")
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

  def client_list
    json.dig('response', 'oauth2_clients')
  end

  def client_obj
    json.dig('response', 'oauth2_client')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def response_errors
    json.dig('response', 'errors') || json['errors']
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list all clients' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = client_list.map { |row| row['id'] }
      expect(ids).to include(primary_client.id, secondary_client.id)

      row = client_list.find { |item| item['id'] == primary_client.id }
      expect(row).to include('id', 'name', 'client_id', 'redirect_uri')
      expect(row).not_to include('client_secret', 'client_secret_hash')
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Oauth2Client.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, oauth2_client: { limit: 1 } }

      expect_status(200)
      expect(client_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = primary_client.id
      as(admin) { json_get index_path, oauth2_client: { from_id: boundary } }

      expect_status(200)
      ids = client_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(primary_client.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get show_path(primary_client.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a client' do
      as(admin) { json_get show_path(primary_client.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(client_obj['id']).to eq(primary_client.id)
      expect(client_obj['name']).to eq('Spec Client A')
      expect(client_obj['client_id']).to eq('spec-client-a')
      expect(client_obj['redirect_uri']).to eq('https://example.invalid/callback-a')
      expect(client_obj).not_to include('client_secret', 'client_secret_hash')
    end

    it 'returns 404 for unknown client' do
      missing = Oauth2Client.maximum(:id).to_i + 100
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, oauth2_client: { name: 'X', client_id: 'x', redirect_uri: 'https://x.invalid', client_secret: 'x' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) do
        json_post index_path, oauth2_client: { name: 'X', client_id: 'x', redirect_uri: 'https://x.invalid', client_secret: 'x' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a client' do
      as(admin) do
        json_post index_path, oauth2_client: {
          name: 'Spec Created',
          client_id: 'spec-created',
          redirect_uri: 'https://example.invalid/callback-created',
          client_secret: 'spec-created-secret'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(client_obj).to be_a(Hash)
      expect(client_obj['name']).to eq('Spec Created')
      expect(client_obj['client_id']).to eq('spec-created')
      expect(client_obj['redirect_uri']).to eq('https://example.invalid/callback-created')
      expect(client_obj).not_to include('client_secret', 'client_secret_hash')

      record = Oauth2Client.find_by!(client_id: 'spec-created')
      expect(record.name).to eq('Spec Created')
      expect(record.check_secret('spec-created-secret')).to be(true)
    end

    it 'returns validation errors for missing name' do
      as(admin) do
        json_post index_path, oauth2_client: {
          client_id: 'spec-missing-name',
          redirect_uri: 'https://example.invalid/callback-missing',
          client_secret: 'spec-missing-secret'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).to be_a(Hash)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for duplicate client_id' do
      as(admin) do
        json_post index_path, oauth2_client: {
          name: 'Spec Duplicate',
          client_id: 'spec-client-a',
          redirect_uri: 'https://example.invalid/callback-dup',
          client_secret: 'spec-dup-secret'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).to be_a(Hash)
      expect(response_errors.keys.map(&:to_s)).to include('client_id')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(primary_client.id), oauth2_client: { name: 'Changed' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put show_path(primary_client.id), oauth2_client: { name: 'Changed' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update client attributes' do
      as(admin) do
        json_put show_path(primary_client.id), oauth2_client: {
          name: 'Spec Client A Updated',
          redirect_uri: 'https://example.invalid/callback-updated'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(client_obj).to be_a(Hash)
      expect(client_obj['name']).to eq('Spec Client A Updated')
      expect(client_obj['redirect_uri']).to eq('https://example.invalid/callback-updated')

      primary_client.reload
      expect(primary_client.name).to eq('Spec Client A Updated')
      expect(primary_client.redirect_uri).to eq('https://example.invalid/callback-updated')
    end

    it 'allows admin to update client secret' do
      old_hash = primary_client.client_secret_hash

      as(admin) { json_put show_path(primary_client.id), oauth2_client: { client_secret: 'spec-new-secret' } }

      expect_status(200)
      expect(json['status']).to be(true)

      primary_client.reload
      expect(primary_client.client_secret_hash).not_to eq(old_hash)
      expect(primary_client.check_secret('spec-new-secret')).to be(true)
    end

    it 'returns validation errors for invalid name' do
      as(admin) { json_put show_path(primary_client.id), oauth2_client: { name: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).to be_a(Hash)
      expect(response_errors.keys.map(&:to_s)).to include('name')
    end

    it 'returns validation errors for duplicate client_id' do
      as(admin) { json_put show_path(primary_client.id), oauth2_client: { client_id: secondary_client.client_id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).to be_a(Hash)
      expect(response_errors.keys.map(&:to_s)).to include('client_id')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(primary_client.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete show_path(primary_client.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a client' do
      as(admin) { json_delete show_path(primary_client.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(Oauth2Client.find_by(id: primary_client.id)).to be_nil
    end
  end
end
