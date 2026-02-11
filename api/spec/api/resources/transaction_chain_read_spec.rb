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
          concerns: [['Vps', 102]]
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

    def create_chain(user:, session:, name:, state:, size:, progress:, concerns: [])
      chain = TransactionChain.create!(
        name: name,
        type: 'TransactionChain',
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

    def json_get(path, params = nil)
      get path, params, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end

    def chains_response
      json.dig('response', 'transaction_chains')
    end

    def chain_obj
      json.dig('response', 'transaction_chain')
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
  end
end
