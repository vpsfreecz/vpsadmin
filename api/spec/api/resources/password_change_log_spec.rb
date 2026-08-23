# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::PasswordChangeLog' do
  let(:fixtures) do
    user_session = create_session(user, 'User password session')
    other_session = create_session(other_user, 'Other password session')
    admin_session = create_session(admin, 'Administrator password session')

    user_change = PasswordChangeLog.create!(
      user:,
      user_session:,
      source: 'authenticated',
      created_at: 3.minutes.ago
    )
    administrator_change = PasswordChangeLog.create!(
      user:,
      user_session: admin_session,
      source: 'administrator',
      created_at: 2.minutes.ago
    )
    recovery_change = PasswordChangeLog.create!(
      user:,
      user_session: nil,
      source: 'recovery',
      created_at: 1.minute.ago
    )
    other_change = PasswordChangeLog.create!(
      user: other_user,
      user_session: other_session,
      source: 'authenticated',
      created_at: Time.current
    )

    {
      user_session:,
      admin_session:,
      user_change:,
      administrator_change:,
      recovery_change:,
      other_change:
    }
  end

  before do
    header 'Accept', 'application/json'
    fixtures
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

  def create_session(user, label)
    UserSession.create!(
      user:,
      auth_type: 'basic',
      api_ip_addr: '192.0.2.101',
      client_ip_addr: '192.0.2.101',
      user_agent: UserAgent.find_or_create!("#{label} agent"),
      client_version: label,
      scope: ['all'],
      label:,
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  def index_path
    vpath('/password_change_logs')
  end

  def show_path(id)
    vpath("/password_change_logs/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def changes
    json.dig('response', 'password_change_logs') || []
  end

  def change
    json.dig('response', 'password_change_log')
  end

  def relation_id(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    message = "Expected #{code}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owners to list only their password changes' do
      as(user) do
        json_get index_path
      end

      expect_status(200)
      ids = changes.map { |row| row['id'] }
      expect(ids).to eq([
                          fixtures[:recovery_change].id,
                          fixtures[:administrator_change].id,
                          fixtures[:user_change].id
                        ])
      expect(ids).not_to include(fixtures[:other_change].id)

      own = changes.find { |row| row['id'] == fixtures[:user_change].id }
      expect(own['user_session_id']).to eq(fixtures[:user_session].id)
      expect(own['user_session_owned_by_user']).to be(true)
      expect(own).not_to have_key('user_session')

      administrator = changes.find do |row|
        row['id'] == fixtures[:administrator_change].id
      end
      expect(administrator['user_session_id']).to eq(fixtures[:admin_session].id)
      expect(administrator['user_session_owned_by_user']).to be(false)
      expect(administrator).not_to have_key('user_session')
      recovery = changes.find { |row| row['id'] == fixtures[:recovery_change].id }
      expect(recovery['user_session_id']).to be_nil
      expect(recovery['user_session_owned_by_user']).to be(false)
    end

    it 'does not expose an administrator through a nested session include to owners' do
      as(user) do
        json_get index_path, _meta: { includes: 'user_session__user' }
      end

      expect_status(200)
      administrator = changes.find do |row|
        row['id'] == fixtures[:administrator_change].id
      end
      expect(administrator).not_to have_key('user_session')
    end

    it 'ignores another-user filters from account owners' do
      as(user) do
        json_get index_path, password_change_log: { user: other_user.id }
      end

      expect_status(200)
      expect(changes.map { |row| relation_id(row['user']) }.uniq).to eq([user.id])
    end

    it 'allows administrators to filter by user, source, and session' do
      as(admin) do
        json_get index_path, password_change_log: {
          user: user.id,
          source: 'administrator',
          user_session_id: fixtures[:admin_session].id
        }, _meta: { includes: 'user_session__user' }
      end

      expect_status(200)
      expect(changes.map { |row| row['id'] }).to eq(
        [fixtures[:administrator_change].id]
      )
      expect(changes.first['user_session_id']).to eq(fixtures[:admin_session].id)
      expect(changes.first.dig('user_session', 'id')).to eq(fixtures[:admin_session].id)
      expect(changes.first.dig('user_session', 'user', 'id')).to eq(admin.id)
      expect(changes.first.dig('user_session', 'user', 'login')).to eq(admin.login)
    end

    it 'supports descending pagination and total counts' do
      as(admin) do
        json_get index_path, password_change_log: {
          limit: 1,
          from_id: fixtures[:recovery_change].id,
          user: user.id
        }, _meta: { count: true }
      end

      expect_status(200)
      expect(changes.map { |row| row['id'] }).to eq(
        [fixtures[:administrator_change].id]
      )
      expect(json.dig('response', '_meta', 'total_count')).to eq(3)
    end
  end

  describe 'Show' do
    it 'allows owners to view their changes but not another account history' do
      as(user) { json_get show_path(fixtures[:user_change].id) }

      expect_status(200)
      expect(change['id']).to eq(fixtures[:user_change].id)

      as(user) { json_get show_path(fixtures[:other_change].id) }

      expect_status(404)
    end

    it 'allows administrators to view every change' do
      as(admin) { json_get show_path(fixtures[:other_change].id) }

      expect_status(200)
      expect(change['id']).to eq(fixtures[:other_change].id)
    end
  end
end
