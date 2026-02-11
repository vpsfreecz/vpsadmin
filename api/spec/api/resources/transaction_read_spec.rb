# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Transaction' do
  describe 'read actions' do
    let(:users) do
      {
        user: SpecSeed.user,
        other_user: SpecSeed.other_user,
        support: SpecSeed.support,
        admin: SpecSeed.admin
      }
    end

    let!(:chains) do
      {
        a: create_chain(user: user, name: 'spec_chain_a', state: :queued, size: 2),
        b: create_chain(user: user, name: 'spec_chain_b', state: :queued, size: 1),
        c: create_chain(user: other_user, name: 'spec_chain_c', state: :done, size: 1)
      }
    end

    let!(:transactions) do
      waiting = ::Transaction.dones.fetch(:waiting)
      done = ::Transaction.dones.fetch(:done)

      {
        t1: create_transaction(
          chain: chain_a,
          handle: 100,
          status: 0,
          done: waiting,
          input: '{"payload":"t1"}',
          output: '{"result":"ok"}',
          urgent: true,
          priority: 10
        ),
        t2: create_transaction(
          chain: chain_a,
          handle: 101,
          status: 1,
          done: done,
          input: '{"payload":"t2"}',
          output: '{"result":"fail"}'
        ),
        t3: create_transaction(
          chain: chain_b,
          handle: 102,
          status: 1,
          done: waiting,
          input: '{"payload":"t3"}',
          output: '{"result":"ok"}'
        ),
        t4: create_transaction(
          chain: chain_c,
          handle: 103,
          status: 0,
          done: done,
          input: '{"payload":"t4"}',
          output: '{"result":"fail"}'
        )
      }
    end

    before do
      header 'Accept', 'application/json'
    end

    def create_chain(user:, name:, state:, size: 1)
      TransactionChain.create!(
        name: name,
        type: 'TransactionChain',
        state: state,
        size: size,
        progress: 0,
        user: user,
        concern_type: :chain_affect
      )
    end

    def create_transaction(chain:, handle:, status:, done:, input:, output:, urgent: false, priority: 0)
      prev_user = ::User.current
      ::User.current = chain.user

      tx = Transaction.create!(
        transaction_chain: chain,
        user: chain.user,
        handle: handle,
        queue: 'general',
        urgent: urgent,
        priority: priority
      )

      tx.update_columns(
        status: status,
        done: done,
        input: input,
        output: output
      )

      tx
    ensure
      ::User.current = prev_user
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

    def chain_a
      chains.fetch(:a)
    end

    def chain_b
      chains.fetch(:b)
    end

    def chain_c
      chains.fetch(:c)
    end

    def t1
      transactions.fetch(:t1)
    end

    def t2
      transactions.fetch(:t2)
    end

    def t3
      transactions.fetch(:t3)
    end

    def t4
      transactions.fetch(:t4)
    end

    def index_path
      vpath('/transactions')
    end

    def show_path(id)
      vpath("/transactions/#{id}")
    end

    def json_get(path, params = nil)
      get path, params, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end

    def txs
      json.dig('response', 'transactions')
    end

    def tx_obj
      json.dig('response', 'transaction')
    end

    def tx_ids
      (txs || []).map { |row| row['id'] }
    end

    def resource_id(value)
      return value['id'] if value.is_a?(Hash)

      value
    end

    def tx_chain_id(row)
      resource_id(row['transaction_chain'])
    end

    def tx_user_id(row)
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

      it 'returns only own transactions for normal users' do
        as(user) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(tx_ids).to include(t1.id, t2.id, t3.id)
        expect(tx_ids).not_to include(t4.id)

        row = txs.find { |item| item['id'] == t1.id }
        expect(row).to include('id', 'transaction_chain', 'success', 'done', 'created_at')
        expect(tx_chain_id(row)).to eq(chain_a.id)
        expect(row).not_to include('user', 'type', 'urgent', 'priority', 'input', 'output')
      end

      it 'returns only own transactions for support users' do
        as(support) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(tx_ids).not_to include(t1.id, t2.id, t3.id, t4.id)
      end

      it 'allows admin to list all transactions' do
        as(admin) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(tx_ids).to include(t1.id, t2.id, t3.id, t4.id)

        row = txs.find { |item| item['id'] == t1.id }
        expect(tx_user_id(row)).to eq(user.id)
        expect(row).to include('user', 'type', 'urgent', 'priority', 'input', 'output')
      end

      it 'supports limit pagination' do
        as(admin) { json_get index_path, transaction: { limit: 1 } }

        expect_status(200)
        expect(txs.length).to eq(1)
      end

      it 'supports from_id pagination' do
        boundary = Transaction.maximum(:id)
        as(admin) { json_get index_path, transaction: { from_id: boundary } }

        expect_status(200)
        ids = txs.map { |row| row['id'].to_i }
        expect(ids.all? { |id| id < boundary }).to be(true)
      end

      it 'returns total_count meta when requested' do
        as(admin) { json_get index_path, _meta: { count: true } }

        expect_status(200)
        expect(json.dig('response', '_meta', 'total_count')).to eq(Transaction.count)
      end

      it 'filters by transaction_chain' do
        as(admin) { json_get index_path, transaction: { transaction_chain: chain_a.id } }

        expect_status(200)
        expect(tx_ids).to contain_exactly(t1.id, t2.id)
      end

      it 'filters by success' do
        as(admin) { json_get index_path, transaction: { success: 1 } }

        expect_status(200)
        expect(tx_ids).to include(t2.id, t3.id)
        expect(tx_ids).not_to include(t1.id, t4.id)
      end

      it 'filters by done' do
        as(admin) { json_get index_path, transaction: { done: 'done' } }

        expect_status(200)
        expect(tx_ids).to include(t2.id, t4.id)
        expect(tx_ids).not_to include(t1.id, t3.id)
      end
    end

    describe 'Show' do
      it 'rejects unauthenticated access' do
        json_get show_path(t1.id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'allows normal users to show their transaction' do
        as(user) { json_get show_path(t1.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(tx_obj['id']).to eq(t1.id)
        expect(tx_chain_id(tx_obj)).to eq(chain_a.id)
        expect(tx_obj['success']).to eq(0)
        expect(tx_obj['done']).to eq('waiting')
        expect(tx_obj).not_to include('user', 'type', 'urgent', 'priority', 'input', 'output')
      end

      it 'hides other users transactions from normal users' do
        as(user) { json_get show_path(t4.id) }

        expect_status(404)
        expect(json['status']).to be(false)
      end

      it 'hides other users transactions from support users' do
        as(support) { json_get show_path(t1.id) }

        expect_status(404)
        expect(json['status']).to be(false)
      end

      it 'allows admin to show any transaction' do
        as(admin) { json_get show_path(t1.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(tx_obj['id']).to eq(t1.id)
        expect(tx_user_id(tx_obj)).to eq(user.id)
        expect(tx_obj['type']).to eq(100)
        expect(tx_obj['urgent']).to be(true)
        expect(tx_obj['priority']).to eq(10)
        expect(tx_obj['input']).to eq('{"payload":"t1"}')
        expect(tx_obj['output']).to eq('{"result":"ok"}')
      end

      it 'returns 404 for unknown transaction' do
        missing = Transaction.maximum(:id).to_i + 100
        as(admin) { json_get show_path(missing) }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end
  end
end
