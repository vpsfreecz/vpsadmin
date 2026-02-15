# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::PublicKey' do
  before do
    header 'Accept', 'application/json'
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }
  let(:key_hello) { 'ssh-ed25519 aGVsbG8= spec@test' }
  let(:key_world) { 'ssh-ed25519 d29ybGQ= spec@test' }

  def index_path(user_id)
    vpath("/users/#{user_id}/public_keys")
  end

  def show_path(user_id, key_id)
    vpath("/users/#{user_id}/public_keys/#{key_id}")
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

  def key_list
    json.dig('response', 'public_keys') || json.dig('response', 'user_public_keys') || []
  end

  def key_obj
    json.dig('response', 'public_key') || json.dig('response', 'user_public_key')
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

  def create_key!(user:, label:, key:, auto_add: false)
    UserPublicKey.create!(user: user, label: label, key: key, auto_add: auto_add)
  end

  describe 'API description' do
    it 'includes user.public_key endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user.public_key#index',
        'user.public_key#show',
        'user.public_key#create',
        'user.public_key#update',
        'user.public_key#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only keys for the requested user when owner' do
      user_key_a = create_key!(user: user, label: 'Spec Key A', key: key_hello, auto_add: false)
      user_key_b = create_key!(user: user, label: 'Spec Key B', key: key_world, auto_add: true)
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = key_list.map { |row| row['id'] }
      expect(ids).to include(user_key_a.id, user_key_b.id)
      expect(ids).not_to include(other_key.id)

      row = key_list.find { |item| item['id'] == user_key_a.id }
      expect(row).to include(
        'id' => user_key_a.id,
        'label' => user_key_a.label,
        'key' => user_key_a.key,
        'auto_add' => user_key_a.auto_add,
        'fingerprint' => user_key_a.fingerprint,
        'comment' => user_key_a.comment
      )
      expect(row['created_at']).not_to be_nil
      expect(row['updated_at']).not_to be_nil
    end

    it 'denies listing keys for another user (non-admin)' do
      create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to list keys for another user' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = key_list.map { |row| row['id'] }
      expect(ids).to include(other_key.id)
    end

    it 'supports limit pagination' do
      create_key!(user: user, label: 'Spec Key A', key: key_hello, auto_add: false)
      create_key!(user: user, label: 'Spec Key B', key: key_world, auto_add: false)

      as(user) { json_get index_path(user.id), public_key: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_list.length).to eq(1)
    end

    it 'returns total_count meta when requested' do
      create_key!(user: user, label: 'Spec Key A', key: key_hello, auto_add: false)
      create_key!(user: user, label: 'Spec Key B', key: key_world, auto_add: false)
      count = UserPublicKey.where(user_id: user.id).count

      as(user) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      json_get show_path(user.id, key.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to show own key' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: true)

      as(user) { json_get show_path(user.id, key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_obj['id']).to eq(key.id)
      expect(key_obj['label']).to eq(key.label)
      expect(key_obj['key']).to eq(key.key)
      expect(key_obj['auto_add']).to eq(key.auto_add)
      expect(key_obj['comment']).to eq(key.comment)
      expect(key_obj['fingerprint']).to match(/\A([0-9a-f]{2}:){15}[0-9a-f]{2}\z/)
      expect(key_obj['created_at']).not_to be_nil
      expect(key_obj['updated_at']).not_to be_nil
    end

    it 'denies showing another user\'s key (non-admin)' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(user) { json_get show_path(other_user.id, other_key.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to show any user\'s key' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(admin) { json_get show_path(other_user.id, other_key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(key_obj['id']).to eq(other_key.id)
    end

    it 'returns 404 for unknown key id (authorized user)' do
      missing = UserPublicKey.maximum(:id).to_i + 100

      as(user) { json_get show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path(user.id), public_key: { label: 'Spec Key', key: key_hello }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create key for themselves' do
      key_input = "  #{key_hello}  "

      as(user) { json_post index_path(user.id), public_key: { label: 'Spec Key', key: key_input } }

      expect_status(200)
      expect(json['status']).to be(true)

      record = UserPublicKey.find_by!(user: user, label: 'Spec Key')
      expect(record.key).to eq(key_hello)
      expect(record.auto_add).to be(false)
      expect(record.comment).to eq('spec@test')
      expect(record.fingerprint).to match(/\A([0-9a-f]{2}:){15}[0-9a-f]{2}\z/)
    end

    it 'denies user creating key for other user' do
      initial = UserPublicKey.where(user_id: other_user.id).count

      as(user) do
        json_post index_path(other_user.id), public_key: { label: 'Spec Key', key: key_hello }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
      expect(UserPublicKey.where(user_id: other_user.id).count).to eq(initial)
    end

    it 'allows admin to create key for other user' do
      as(admin) do
        json_post index_path(other_user.id), public_key: { label: 'Spec Key', key: key_hello }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      record = UserPublicKey.find_by!(user_id: other_user.id, label: 'Spec Key')
      expect(record.user_id).to eq(other_user.id)
    end

    it 'returns validation errors for missing label' do
      as(user) { json_post index_path(user.id), public_key: { key: key_hello } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing key' do
      as(user) { json_post index_path(user.id), public_key: { label: 'Spec Key' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('key')
    end

    it 'rejects key with line breaks' do
      as(user) do
        json_post index_path(user.id), public_key: { label: 'Spec Key', key: "ssh-ed25519 aGVsbG8=\nspec@test" }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('key')
    end

    it 'rejects private key upload' do
      as(user) do
        json_post index_path(user.id), public_key: {
          label: 'Spec Key',
          key: '-----BEGIN RSA PRIVATE KEY-----'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('key')
      message = Array(response_errors['key']).join(' ')
      expect(message).to match(/never upload your private key/i)
    end

    it 'rejects structurally invalid public key' do
      as(user) { json_post index_path(user.id), public_key: { label: 'Spec Key', key: 'ssh-ed25519' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('key')
      message = Array(response_errors['key']).join(' ')
      expect(message).to match(/invalid public key/i)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      json_put show_path(user.id, key.id), public_key: { label: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to update label and auto_add' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      as(user) do
        json_put show_path(user.id, key.id), public_key: { label: 'Updated', auto_add: true }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      key.reload
      expect(key.label).to eq('Updated')
      expect(key.auto_add).to be(true)
    end

    it 'allows owner to update key and strips whitespace' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)
      old_fingerprint = key.fingerprint
      new_key = '  ssh-ed25519 d29ybGQ= new@comment  '

      as(user) { json_put show_path(user.id, key.id), public_key: { key: new_key } }

      expect_status(200)
      expect(json['status']).to be(true)
      key.reload
      expect(key.key).to eq('ssh-ed25519 d29ybGQ= new@comment')
      expect(key.comment).to eq('new@comment')
      expect(key.fingerprint).to match(/\A([0-9a-f]{2}:){15}[0-9a-f]{2}\z/)
      expect(key.fingerprint).not_to eq(old_fingerprint)
      expect(key_obj['comment']).to eq('new@comment')
      expect(key_obj['fingerprint']).to eq(key.fingerprint)
    end

    it 'returns error when input is empty' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      as(user) { json_put show_path(user.id, key.id), public_key: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/provide at least one input parameter/i)
    end

    it 'denies updating other user\'s key (non-admin)' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(user) do
        json_put show_path(other_user.id, other_key.id), public_key: { label: 'Nope' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'returns validation errors for invalid key' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      as(user) { json_put show_path(user.id, key.id), public_key: { key: 'ssh-ed25519' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('key')
    end

    it 'returns 404 for unknown key id (authorized)' do
      missing = UserPublicKey.maximum(:id).to_i + 100

      as(user) { json_put show_path(user.id, missing), public_key: { label: 'Spec Key' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      json_delete show_path(user.id, key.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to delete own key' do
      key = create_key!(user: user, label: 'Spec Key', key: key_hello, auto_add: false)

      as(user) { json_delete show_path(user.id, key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserPublicKey.exists?(key.id)).to be(false)
    end

    it 'denies deleting other user\'s key (non-admin)' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(user) { json_delete show_path(other_user.id, other_key.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to delete any user\'s key' do
      other_key = create_key!(user: other_user, label: 'Other Key', key: key_hello, auto_add: false)

      as(admin) { json_delete show_path(other_user.id, other_key.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserPublicKey.exists?(other_key.id)).to be(false)
    end

    it 'returns 404 for unknown key id (authorized)' do
      missing = UserPublicKey.maximum(:id).to_i + 100

      as(user) { json_delete show_path(user.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
