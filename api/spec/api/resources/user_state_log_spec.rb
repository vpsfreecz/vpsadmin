# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::StateLog' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.support
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.environment
    seed
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }
  let(:support) { SpecSeed.support }
  let(:other_user) { SpecSeed.other_user }
  let(:seed) do
    base = Time.utc(2040, 1, 1, 12, 0, 0)

    ObjectState.where(class_name: User.name, row_id: [user.id, other_user.id]).delete_all

    a = create_state_log!(
      target_user: user,
      changed_by: admin,
      state: :active,
      reason: 'seed-a',
      created_at: base + 10,
      expiration: base + 3600,
      remind_after: base + 1800
    )

    b = create_state_log!(
      target_user: user,
      changed_by: admin,
      state: :suspended,
      reason: 'seed-b',
      created_at: base + 20
    )

    c = create_state_log!(
      target_user: user,
      changed_by: admin,
      state: :soft_delete,
      reason: 'seed-c',
      created_at: base + 30
    )

    other = create_state_log!(
      target_user: other_user,
      changed_by: admin,
      state: :active,
      reason: 'seed-other',
      created_at: base + 40
    )

    noise = ObjectState.create!(
      class_name: 'Environment',
      row_id: SpecSeed.environment.id,
      state: :active,
      reason: 'noise',
      user: admin,
      created_at: base + 50,
      updated_at: base + 50
    )

    { a: a, b: b, c: c, other: other, noise: noise }
  end

  def index_path(user_id)
    vpath("/users/#{user_id}/state_logs")
  end

  def show_path(user_id, state_log_id)
    vpath("/users/#{user_id}/state_logs/#{state_log_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def logs
    json.dig('response', 'state_logs')
  end

  def log_obj
    json.dig('response', 'state_log') || json['response']
  end

  def response_meta_total
    json.dig('response', '_meta', 'total_count')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_state_log!(target_user:, changed_by:, state:, reason:, created_at:, expiration: nil, remind_after: nil)
    ObjectState.create!(
      class_name: User.name,
      row_id: target_user.id,
      state: state,
      reason: reason,
      user: changed_by,
      expiration_date: expiration,
      remind_after_date: remind_after,
      created_at: created_at,
      updated_at: created_at
    )
  end

  describe 'API description' do
    it 'includes user.state_log scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('user.state_log#index', 'user.state_log#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get index_path(user.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) { json_get index_path(user.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to list logs for a specific user' do
      as(admin) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(logs).to be_an(Array)

      ids = logs.map { |row| row['id'] }
      expect(ids).to eq([seed[:a].id, seed[:b].id, seed[:c].id])
    end

    it 'returns expected output shape' do
      as(admin) { json_get index_path(user.id) }

      expect_status(200)
      row = logs.find { |item| item['id'] == seed[:a].id }
      expect(row).to include('id', 'state', 'changed_at', 'reason', 'expiration', 'remind_after', 'user')
      expect(row['state']).to eq('active')
      expect(row['user']).to be_a(Hash)
      expect(row['user']).to include('id', 'login')
      expect(row['user']['id']).to eq(admin.id)
      expect(row['expiration']).not_to be_nil
      expect(row['remind_after']).not_to be_nil
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path(user.id), state_log: { limit: 2 } }

      expect_status(200)
      expect(logs.length).to eq(2)
      ids = logs.map { |row| row['id'] }
      expect(ids).to eq([seed[:a].id, seed[:b].id])
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(response_meta_total).to eq(3)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user.id, seed[:a].id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get show_path(user.id, seed[:a].id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a log entry' do
      as(admin) { json_get show_path(user.id, seed[:b].id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(log_obj['id']).to eq(seed[:b].id)
      expect(log_obj['state']).to eq('suspended')
      expect(log_obj['user']).to be_a(Hash)
    end

    it 'does not allow showing another user log under the wrong parent' do
      as(admin) { json_get show_path(user.id, seed[:other].id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'returns not found for unknown id' do
      missing = ObjectState.maximum(:id).to_i + 100
      as(admin) { json_get show_path(user.id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
