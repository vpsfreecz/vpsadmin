# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::TransactionChain' do
  describe 'read actions' do
    let(:users) do
      {
        user: SpecSeed.user,
        other_user: SpecSeed.other_user,
        support: SpecSeed.support,
        admin: SpecSeed.admin
      }
    end

    let!(:sessions) do
      {
        user: create_session(
          user: user,
          ip: '192.0.2.10',
          user_agent: 'SpecUA/TC1',
          label: 'Spec Chain User'
        ),
        other_user: create_session(
          user: other_user,
          ip: '192.0.2.20',
          user_agent: 'SpecUA/TC2',
          label: 'Spec Chain Other'
        ),
        support: create_session(
          user: support,
          ip: '192.0.2.30',
          user_agent: 'SpecUA/TC3',
          label: 'Spec Chain Support'
        )
      }
    end

    let!(:chains) do
      {
        a: create_chain(
          user: user,
          session: session_user,
          name: 'spec_chain_a',
          state: :queued,
          size: 2,
          progress: 0,
          concerns: [['Vps', 101]]
        ),
        b: create_chain(
          user: user,
          session: session_user,
          name: 'spec_chain_b',
          state: :done,
          size: 1,
          progress: 1,
          concerns: [['Vps', 102]],
          type: 'TransactionChains::Vps::Start'
        ),
        c: create_chain(
          user: other_user,
          session: session_other_user,
          name: 'spec_chain_c',
          state: :failed,
          size: 1,
          progress: 0,
          concerns: [['DnsZone', 201]]
        ),
        d: create_chain(
          user: support,
          session: session_support,
          name: 'spec_chain_d',
          state: :queued,
          size: 1,
          progress: 0,
          concerns: [['DnsZone', 202]]
        )
      }
    end

    before do
      header 'Accept', 'application/json'
      create_transaction(chain_a, 1)
      create_transaction(chain_a, 2)
      create_transaction(chain_b, 3)
      create_transaction(chain_c, 4)
      create_transaction(chain_d, 5)
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

    def create_chain(user:, session:, name:, state:, size:, progress:, concerns: [], type: 'TransactionChain')
      chain = TransactionChain.create!(
        name: name,
        type: type,
        state: state,
        size: size,
        progress: progress,
        user: user,
        user_session: session,
        concern_type: :chain_affect
      )

      concerns.each do |klass, row_id|
        TransactionChainConcern.create!(
          transaction_chain: chain,
          class_name: klass,
          row_id: row_id
        )
      end

      chain
    end

    def create_transaction(chain, handle)
      Transaction.create!(
        transaction_chain: chain,
        handle: handle,
        queue: 'general'
      )
    end

    def user
      users.fetch(:user)
    end

    def other_user
      users.fetch(:other_user)
    end

    def support
      users.fetch(:support)
    end

    def admin
      users.fetch(:admin)
    end

    def session_user
      sessions.fetch(:user)
    end

    def session_other_user
      sessions.fetch(:other_user)
    end

    def session_support
      sessions.fetch(:support)
    end

    def chain_a
      chains.fetch(:a)
    end

    def chain_b
      chains.fetch(:b)
    end

    def chain_c
      chains.fetch(:c)
    end

    def chain_d
      chains.fetch(:d)
    end

    def index_path
      vpath('/transaction_chains')
    end

    def show_path(id)
      vpath("/transaction_chains/#{id}")
    end

    def notify_when_done_path(id)
      vpath("/transaction_chains/#{id}/notify_when_done")
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

    def chains_response
      json.dig('response', 'transaction_chains')
    end

    def chain_obj
      json.dig('response', 'transaction_chain')
    end

    def route_obj
      json.dig('response', 'event_route') || json['response']
    end

    def resource_id(value)
      return value['id'] if value.is_a?(Hash)

      value
    end

    def chain_user_id(row)
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

      it 'returns only own chains for normal users' do
        as(user) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_a.id, chain_b.id)
        expect(ids).not_to include(chain_c.id, chain_d.id)

        row = chains_response.find { |item| item['id'] == chain_a.id }
        expect(row).to include('id', 'state', 'size', 'progress', 'created_at', 'concerns')
        expect(row).not_to have_key('user')
        expect(row.dig('concerns', 'type')).to eq('affect')
        expect(row.dig('concerns', 'objects')).to include(['Vps', 101])
      end

      it 'returns only own chains for support users' do
        as(support) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_d.id)
        expect(ids).not_to include(chain_a.id, chain_b.id, chain_c.id)
      end

      it 'allows admin to list all chains' do
        as(admin) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_a.id, chain_b.id, chain_c.id, chain_d.id)

        row = chains_response.find { |item| item['id'] == chain_a.id }
        expect(chain_user_id(row)).to eq(user.id)
      end

      it 'supports limit pagination' do
        as(admin) { json_get index_path, transaction_chain: { limit: 1 } }

        expect_status(200)
        expect(chains_response.length).to eq(1)
      end

      it 'supports from_id pagination' do
        boundary = TransactionChain.maximum(:id)
        as(admin) { json_get index_path, transaction_chain: { from_id: boundary } }

        expect_status(200)
        ids = chains_response.map { |row| row['id'].to_i }
        expect(ids.all? { |id| id < boundary }).to be(true)
      end

      it 'returns total_count meta when requested' do
        as(admin) { json_get index_path, _meta: { count: true } }

        expect_status(200)
        expect(json.dig('response', '_meta', 'total_count')).to eq(TransactionChain.count)
      end

      it 'filters by user for admins' do
        as(admin) { json_get index_path, transaction_chain: { user: user.id } }

        expect_status(200)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_a.id, chain_b.id)
        expect(ids).not_to include(chain_c.id, chain_d.id)
      end

      it 'filters by state' do
        as(admin) { json_get index_path, transaction_chain: { state: 'queued' } }

        expect_status(200)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_a.id, chain_d.id)
        expect(ids).not_to include(chain_b.id, chain_c.id)
      end

      it 'filters by class_name' do
        as(admin) { json_get index_path, transaction_chain: { class_name: 'Vps' } }

        expect_status(200)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to include(chain_a.id, chain_b.id)
        expect(ids).not_to include(chain_c.id, chain_d.id)
      end

      it 'filters by row_id' do
        as(admin) { json_get index_path, transaction_chain: { row_id: 201 } }

        expect_status(200)
        ids = chains_response.map { |row| row['id'] }
        expect(ids).to eq([chain_c.id])
      end
    end

    describe 'Show' do
      it 'rejects unauthenticated access' do
        json_get show_path(chain_a.id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'allows normal users to show their chain' do
        as(user) { json_get show_path(chain_a.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(chain_obj['id']).to eq(chain_a.id)
        expect(chain_obj['state']).to eq('queued')
        expect(chain_obj['size']).to eq(2)
        expect(chain_obj['progress']).to eq(0)
        expect(chain_obj).not_to have_key('user')
        expect(chain_obj['created_at']).not_to be_nil
        expect(chain_obj.dig('concerns', 'type')).to eq('affect')
        expect(chain_obj.dig('concerns', 'objects')).to include(['Vps', 101])
      end

      it 'hides other users chains from normal users' do
        as(user) { json_get show_path(chain_c.id) }

        expect_status(404)
        expect(json['status']).to be(false)
      end

      it 'hides other users chains from support users' do
        as(support) { json_get show_path(chain_a.id) }

        expect_status(404)
        expect(json['status']).to be(false)
      end

      it 'allows admin to show any chain' do
        as(admin) { json_get show_path(chain_c.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(chain_obj['id']).to eq(chain_c.id)
        expect(chain_user_id(chain_obj)).to eq(other_user.id)
      end

      it 'returns 404 for unknown chain' do
        missing = TransactionChain.maximum(:id).to_i + 100
        as(admin) { json_get show_path(missing) }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end

    describe 'NotifyWhenDone' do
      before do
        EventRouteMatch.delete_all
        EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
        NotificationReceiverAction
          .joins(:notification_receiver)
          .where(notification_receivers: { user_id: user.id })
          .delete_all
        EventRoute.where(user: user).delete_all
        NotificationReceiver.where(user: user).delete_all
      end

      it 'creates a top-position single-use route for terminal state changes' do
        receiver = NotificationReceiver.create!(user:, label: 'Spec receiver')
        receiver.notification_receiver_actions.create!(
          action: :webhook,
          target_kind: :custom,
          target_value: 'https://example.test/chain'
        )

        as(user) do
          json_post notify_when_done_path(chain_a.id), transaction_chain: {
            notification_receiver_id: receiver.id
          }
        end

        expect_status(200)
        route = EventRoute.find(route_obj['id'])

        expect(route).to be_single_use
        expect(route.spent_at).to be_nil
        expect(route.position).to eq(EventRoute.minimum(:position))
        expect(route.event_type).to eq('transaction_chain.state_changed')
        matcher_rows = route.event_route_matchers.map { |m| [m.field, m.operator, m.value] }
        timestamp_matcher = route.event_route_matchers.find_by!(field: 'parameters.changed_at_timestamp')
        expect(matcher_rows).to include(
          ['source_class', '==', 'TransactionChain'],
          ['source_id', '==', chain_a.id.to_s],
          ['parameters.terminal', '==', 'true']
        )
        expect(timestamp_matcher.operator).to eq('>=')
        expect(Float(timestamp_matcher.value)).to be <= Time.now.to_f
        expect(route.event_route_matchers.count).to eq(4)
      end

      it 'spends the route immediately when the chain is already terminal' do
        receiver = NotificationReceiver.create!(user:, label: 'Spec terminal receiver')
        receiver.notification_receiver_actions.create!(
          action: :webhook,
          target_kind: :custom,
          target_value: 'https://example.test/chain-done'
        )

        as(user) do
          json_post notify_when_done_path(chain_b.id), transaction_chain: {
            notification_receiver_id: receiver.id
          }
        end

        expect_status(200)
        route = EventRoute.find(route_obj['id'])
        event = Event.where(event_type: 'transaction_chain.state_changed', source_class: 'TransactionChain',
                            source_id: chain_b.id).sole

        expect(route.reload.spent_at).to be_present
        expect(route).not_to be_enabled
        expect(event.event_route_matches.reload.map(&:event_route)).to eq([route])
        expect(event.parameters).to include(
          'state' => 'done',
          'terminal' => true,
          'successful' => true,
          'failed' => false
        )
        expect(event.event_deliveries.sole.notification_receiver).to eq(receiver)
      end

      it 'ignores terminal state changes that happened before the route was created' do
        receiver = NotificationReceiver.create!(user:, label: 'Spec retry receiver')
        receiver.notification_receiver_actions.create!(
          action: :webhook,
          target_kind: :custom,
          target_value: 'https://example.test/chain-retry'
        )

        as(user) do
          json_post notify_when_done_path(chain_a.id), transaction_chain: {
            notification_receiver_id: receiver.id
          }
        end

        expect_status(200)
        route = EventRoute.find(route_obj['id'])
        threshold = Float(route.event_route_matchers.find_by!(field: 'parameters.changed_at_timestamp').value)

        stale_event = VpsAdmin::API::Events.emit_transaction_chain_state!(
          chain_a,
          previous_state: 'rollbacking',
          state: 'failed',
          changed_at: Time.at(threshold - 60)
        )

        expect(stale_event).to be_nil
        expect(route.reload.spent_at).to be_nil

        fresh_event = VpsAdmin::API::Events.emit_transaction_chain_state!(
          chain_a,
          previous_state: 'queued',
          state: 'done',
          changed_at: Time.at(threshold + 60)
        )

        expect(fresh_event.reload.event_route_matches.map(&:event_route)).to eq([route])
        expect(route.reload.spent_at).to be_present
      end

      it 'repairs the default receiver when no receiver is selected' do
        NotificationReceiver.create!(user:, label: 'Custom receiver')

        as(user) { json_post notify_when_done_path(chain_a.id), transaction_chain: {} }

        expect_status(200)
        route = EventRoute.find(route_obj['id'])
        receiver = route.notification_receiver

        expect(receiver.label).to eq(NotificationReceiver::DEFAULT_EMAIL_LABEL)
        expect(receiver.notification_receiver_actions.sole.action).to eq('email')
      end

      it 'does not let users create routes for other users chains' do
        as(user) { json_post notify_when_done_path(chain_c.id), transaction_chain: {} }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end
  end
end
