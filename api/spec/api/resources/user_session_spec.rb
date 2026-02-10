# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserSession' do
  before do
    header 'Accept', 'application/json'
  end

  let(:users) do
    {
      user: SpecSeed.user,
      other_user: SpecSeed.other_user,
      admin: SpecSeed.admin,
      support: SpecSeed.support
    }
  end

  let!(:sessions) do
    {
      user_primary: create_session(
        user: user,
        ip: '192.0.2.10',
        user_agent: 'SpecUA/1',
        label: 'Spec Session 1'
      ),
      user_secondary: create_session(
        user: user,
        ip: '192.0.2.11',
        user_agent: 'SpecUA/2',
        label: 'Spec Session 2'
      ),
      other_user: create_session(
        user: other_user,
        ip: '192.0.2.20',
        user_agent: 'SpecUA/3',
        label: 'Spec Session 3'
      ),
      support: create_session(
        user: support,
        ip: '192.0.2.30',
        user_agent: 'SpecUA/4',
        label: 'Support Session'
      )
    }
  end

  def create_session(user:, ip:, user_agent:, label:)
    UserSession.create!(
      user: user,
      auth_type: 'basic',
      api_ip_addr: ip,
      client_ip_addr: ip,
      user_agent: UserAgent.find_or_create!(user_agent),
      client_version: user_agent,
      scope: ['all'],
      label: label,
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  def user
    users.fetch(:user)
  end

  def other_user
    users.fetch(:other_user)
  end

  def admin
    users.fetch(:admin)
  end

  def support
    users.fetch(:support)
  end

  def session_user_primary
    sessions.fetch(:user_primary)
  end

  def session_user_secondary
    sessions.fetch(:user_secondary)
  end

  def session_other_user
    sessions.fetch(:other_user)
  end

  def session_support
    sessions.fetch(:support)
  end

  def index_path
    vpath('/user_sessions')
  end

  def show_path(id)
    vpath("/user_sessions/#{id}")
  end

  def close_path(id)
    show_path(id)
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

  def sessions
    json.dig('response', 'user_sessions')
  end

  def session_obj
    json.dig('response', 'user_session')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def session_user_id(row)
    resource_id(row['user'])
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list only their sessions' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = sessions.map { |row| row['id'] }
      expect(ids).to include(session_user_primary.id, session_user_secondary.id)
      expect(ids).not_to include(session_other_user.id)

      row = sessions.find { |s| s['id'] == session_user_primary.id }
      expect(row['api_ip_addr']).to eq('192.0.2.10')
      expect(row['user_agent']).to eq('SpecUA/1')
      expect(row['scope']).to eq('all')
      expect(row['created_at']).not_to be_nil
    end

    it 'ignores user filter for normal users' do
      as(user) { json_get index_path, user_session: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = sessions.map { |row| row['id'] }
      expect(ids).to include(session_user_primary.id, session_user_secondary.id)
      expect(ids).not_to include(session_other_user.id)
    end

    it 'allows support users to list only their sessions' do
      as(support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = sessions.map { |row| row['id'] }
      expect(ids).to include(session_support.id)
      expect(ids).not_to include(session_user_primary.id, session_other_user.id)
    end

    it 'allows admin to list all sessions' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = sessions.map { |row| row['id'] }
      expect(ids).to include(
        session_user_primary.id,
        session_user_secondary.id,
        session_other_user.id,
        session_support.id
      )
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(UserSession.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, user_session: { limit: 1 } }

      expect_status(200)
      expect(sessions.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = UserSession.maximum(:id)
      as(admin) { json_get index_path, user_session: { from_id: boundary } }

      expect_status(200)
      ids = sessions.map { |row| row['id'].to_i }
      expect(ids.all? { |id| id < boundary }).to be(true)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(session_user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to show their session' do
      as(user) { json_get show_path(session_user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_obj['id']).to eq(session_user_primary.id)
      expect(session_user_id(session_obj)).to eq(user.id)
      expect(session_obj['api_ip_addr']).to eq('192.0.2.10')
      expect(session_obj['user_agent']).to eq('SpecUA/1')
    end

    it 'hides other users sessions from normal users' do
      as(user) { json_get show_path(session_other_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any session' do
      as(admin) { json_get show_path(session_other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_user_id(session_obj)).to eq(other_user.id)
    end

    it 'returns 404 for unknown session' do
      missing = UserSession.maximum(:id).to_i + 100
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, user_session: { user: user.id, token_lifetime: 'fixed', token_interval: 3600 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) do
        json_post index_path, user_session: { user: user.id, token_lifetime: 'fixed', token_interval: 3600 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) do
        json_post index_path, user_session: { user: user.id, token_lifetime: 'fixed', token_interval: 3600 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a token session' do
      as(admin) do
        json_post index_path, user_session: {
          user: user.id,
          token_lifetime: 'fixed',
          token_interval: 3600,
          scope: 'all',
          label: 'Spec token'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_user_id(session_obj)).to eq(user.id)
      expect(session_obj['auth_type']).to eq('token')
      expect(session_obj['token_full']).not_to be_nil
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(session_user_primary.id), user_session: { label: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to update their session label' do
      as(user) { json_put show_path(session_user_primary.id), user_session: { label: 'Updated' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_user_primary.reload.label).to eq('Updated')
    end

    it 'hides other users sessions from normal users' do
      as(user) { json_put show_path(session_other_user.id), user_session: { label: 'Nope' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update any session label' do
      as(admin) { json_put show_path(session_other_user.id), user_session: { label: 'Admin Updated' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_other_user.reload.label).to eq('Admin Updated')
    end
  end

  describe 'Close' do
    it 'rejects unauthenticated access' do
      json_post close_path(session_user_primary.id), {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to close their session' do
      as(user) { json_post close_path(session_user_primary.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_user_primary.reload.closed_at).not_to be_nil
    end

    it 'hides other users sessions from normal users' do
      as(user) { json_post close_path(session_other_user.id), {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to close any session' do
      as(admin) { json_post close_path(session_other_user.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(session_other_user.reload.closed_at).not_to be_nil
    end

    it 'is idempotent for repeated close' do
      as(user) { json_post close_path(session_user_secondary.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)

      as(user) { json_post close_path(session_user_secondary.id), {} }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end
end
