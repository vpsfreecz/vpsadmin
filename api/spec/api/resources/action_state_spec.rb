# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::ActionState' do
  let(:users) do
    {
      user: SpecSeed.user,
      other_user: SpecSeed.other_user
    }
  end

  let!(:sessions) do
    {
      user: create_session(
        user: user,
        ip: '192.0.2.10',
        user_agent: 'SpecUA/AS1',
        label: 'Spec ActionState User'
      ),
      other_user: create_session(
        user: other_user,
        ip: '192.0.2.20',
        user_agent: 'SpecUA/AS2',
        label: 'Spec ActionState Other'
      )
    }
  end

  let!(:chains) do
    {
      queued: create_chain(
        user: user,
        session: session_user,
        name: 'spec_action_state_queued',
        state: :queued,
        size: 3,
        progress: 1
      ),
      rollback: create_chain(
        user: user,
        session: session_user,
        name: 'spec_action_state_rollback',
        state: :rollbacking,
        size: 2,
        progress: 0
      ),
      done: create_chain(
        user: user,
        session: session_user,
        name: 'spec_action_state_done',
        state: :done,
        size: 1,
        progress: 1
      ),
      failed: create_chain(
        user: user,
        session: session_user,
        name: 'spec_action_state_failed',
        state: :failed,
        size: 2,
        progress: 1
      ),
      other_queued: create_chain(
        user: other_user,
        session: session_other_user,
        name: 'spec_action_state_other_queued',
        state: :queued,
        size: 1,
        progress: 0
      )
    }
  end

  before do
    header 'Accept', 'application/json'
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

  def create_chain(user:, session:, name:, state:, size:, progress:)
    TransactionChain.create!(
      name: name,
      type: 'TransactionChain',
      state: state,
      size: size,
      progress: progress,
      user: user,
      user_session: session,
      concern_type: :chain_affect
    )
  end

  def user
    users.fetch(:user)
  end

  def other_user
    users.fetch(:other_user)
  end

  def session_user
    sessions.fetch(:user)
  end

  def session_other_user
    sessions.fetch(:other_user)
  end

  def queued_chain
    chains.fetch(:queued)
  end

  def rollback_chain
    chains.fetch(:rollback)
  end

  def done_chain
    chains.fetch(:done)
  end

  def failed_chain
    chains.fetch(:failed)
  end

  def other_queued_chain
    chains.fetch(:other_queued)
  end

  def index_path
    vpath('/action_states')
  end

  def show_path(id)
    vpath("/action_states/#{id}")
  end

  def poll_path(id)
    vpath("/action_states/#{id}/poll")
  end

  def cancel_path(id)
    vpath("/action_states/#{id}/cancel")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload = {})
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def action_states
    json.dig('response', 'action_states')
  end

  def action_state
    json.dig('response', 'action_state')
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

  def missing_chain_id
    TransactionChain.maximum(:id).to_i + 100
  end

  describe 'Index' do
    it 'returns empty list for unauthenticated requests' do
      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_states).to be_a(Array)
      expect(action_states).to be_empty
    end

    it 'lists only queued and rollbacking chains for the current user' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = action_states.map { |row| row['id'] }
      expect(ids).to include(queued_chain.id, rollback_chain.id)
      expect(ids).not_to include(done_chain.id, failed_chain.id, other_queued_chain.id)

      queued_row = action_states.detect { |row| row['id'] == queued_chain.id }
      expect(queued_row).to include(
        'id',
        'label',
        'finished',
        'status',
        'current',
        'total',
        'unit',
        'can_cancel',
        'created_at',
        'updated_at'
      )
      expect(queued_row['finished']).to be(false)
      expect(queued_row['status']).to be(true)
      expect(queued_row['current']).to eq(queued_chain.progress)
      expect(queued_row['total']).to eq(queued_chain.size)
      expect(queued_row['unit']).to eq('transactions')
      expect(queued_row['can_cancel']).to be(false)

      rollback_row = action_states.detect { |row| row['id'] == rollback_chain.id }
      expect(rollback_row['finished']).to be(false)
      expect(rollback_row['status']).to be(false)
    end

    it 'orders by newest by default and oldest when requested' do
      as(user) { json_get index_path }

      ids = action_states.map { |row| row['id'] }
      expect(ids).to eq(ids.sort.reverse)

      as(user) { json_get index_path, action_state: { order: 'oldest' } }

      ids = action_states.map { |row| row['id'] }
      expect(ids).to eq(ids.sort)
    end

    it 'supports limit pagination' do
      as(user) { json_get index_path, action_state: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_states.size).to eq(1)
    end

    it 'supports from_id pagination' do
      as(user) { json_get index_path, action_state: { order: 'oldest', from_id: queued_chain.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = action_states.map { |row| row['id'] }
      expect(ids).to all(be > queued_chain.id)
    end

    it 'validates order choices' do
      as(user) { json_get index_path, action_state: { order: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('order')
    end
  end

  describe 'Show' do
    it 'treats unauthenticated requests as not found' do
      json_get show_path(queued_chain.id)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'shows a chain owned by the current user' do
      as(user) { json_get show_path(queued_chain.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state['id']).to eq(queued_chain.id)
      expect(action_state['finished']).to be(false)
      expect(action_state['status']).to be(true)
      expect(action_state['current']).to eq(queued_chain.progress)
      expect(action_state['total']).to eq(queued_chain.size)
      expect(action_state['unit']).to eq('transactions')
      expect(action_state['can_cancel']).to be(false)
    end

    it 'hides other user chains' do
      as(user) { json_get show_path(other_queued_chain.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'marks done chains as finished with success' do
      as(user) { json_get show_path(done_chain.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state['finished']).to be(true)
      expect(action_state['status']).to be(true)
    end

    it 'marks failed chains as finished with failure' do
      as(user) { json_get show_path(failed_chain.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state['finished']).to be(true)
      expect(action_state['status']).to be(false)
    end

    it 'returns not found for unknown ids' do
      as(user) { json_get show_path(missing_chain_id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end
  end

  describe 'Poll' do
    it 'returns immediately with timeout 0' do
      as(user) { json_get poll_path(queued_chain.id), action_state: { timeout: 0 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state['id']).to eq(queued_chain.id)
      expect(action_state['finished']).to be(false)
      expect(action_state['status']).to be(true)
      expect(action_state['current']).to eq(queued_chain.progress)
      expect(action_state['total']).to eq(queued_chain.size)
      expect(action_state['unit']).to eq('transactions')
      expect(action_state['can_cancel']).to be(false)
    end

    it 'returns immediately when update_in criteria mismatch' do
      as(user) do
        json_get poll_path(queued_chain.id), action_state: {
          timeout: 10,
          update_in: 1,
          status: false,
          current: 999,
          total: 999
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state['status']).to be(true)
      expect(action_state['current']).to eq(queued_chain.progress)
      expect(action_state['total']).to eq(queued_chain.size)
    end

    it 'treats unauthenticated requests as not found' do
      json_get poll_path(queued_chain.id), action_state: { timeout: 0 }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'hides other user chains' do
      as(user) { json_get poll_path(other_queued_chain.id), action_state: { timeout: 0 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'returns not found for unknown ids' do
      as(user) { json_get poll_path(missing_chain_id), action_state: { timeout: 0 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end
  end

  describe 'Cancel' do
    it 'treats unauthenticated requests as not found' do
      json_post cancel_path(queued_chain.id)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'returns not implemented for authenticated users' do
      as(user) { json_post cancel_path(queued_chain.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action cancellation is not implemented/i)
    end

    it 'hides other user chains' do
      as(user) { json_post cancel_path(other_queued_chain.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end

    it 'returns not found for unknown ids' do
      as(user) { json_post cancel_path(missing_chain_id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/action state not found/i)
    end
  end
end
