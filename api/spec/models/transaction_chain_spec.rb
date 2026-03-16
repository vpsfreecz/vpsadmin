# frozen_string_literal: true

require 'json'

module SpecTransactions
  class ChainTx < ::Transaction
    t_type 990_010
    queue :general

    def params(node, tag:)
      self.node = node

      {
        node_id: node.id,
        tag:
      }
    end
  end
end

module SpecChains
  class Empty < ::TransactionChain
    def link_chain(*)
      nil
    end
  end

  class AllowedEmpty < ::TransactionChain
    allow_empty

    def link_chain(*)
      nil
    end
  end

  class AllowedEmptyLocked < ::TransactionChain
    allow_empty

    def link_chain(lock_target)
      lock(lock_target)
      nil
    end
  end

  class Linear < ::TransactionChain
    def link_chain(node)
      seen_state = state.to_sym

      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'first' }, name: :first)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'second' }, name: :second)

      seen_state
    end
  end

  class Anchored < ::TransactionChain
    def link_chain(node)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'root' }, name: :root)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'tail' }, name: :tail)
      append_to(:root, SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'branch' }, name: :branch)
    end
  end

  class NoopChain < ::TransactionChain
    def link_chain(node)
      self.last_node_id = node.id

      append_or_noop_t(SpecTransactions::ChainTx, noop: true) do |confirmable|
        row = ResourceLock.create!(resource: 'SpecLock', row_id: 77)
        confirmable.just_destroy(row)
      end
    end
  end

  class Inner < ::TransactionChain
    def link_chain(node, lock_target)
      lock(lock_target)
      concerns(:affect, [lock_target.class.name, lock_target.id])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'inner-1' }, name: :inner1)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'inner-2' }, name: :inner2)
    end
  end

  class Outer < ::TransactionChain
    def link_chain(node, lock_target)
      lock(lock_target)
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'outer-1' }, name: :outer1)
      use_chain(SpecChains::Inner, args: [node, lock_target])
      append_t(SpecTransactions::ChainTx, args: [node], kwargs: { tag: 'outer-2' }, name: :outer2)
      concerns(:affect, [lock_target.class.name, lock_target.id])
    end
  end

  class ContextProbe < ::TransactionChain
    def link_chain
      [included?, current_chain]
    end
  end
end

RSpec.describe TransactionChain do
  let(:node) do
    SpecSeed.node.tap do |n|
      n.update!(active: true) unless n.active?
    end
  end
  let(:lock_target) do
    UserClusterResource.find_by!(
      user: SpecSeed.user,
      environment: SpecSeed.environment,
      cluster_resource: ClusterResource.find_by!(name: 'ipv4')
    )
  end

  around do |example|
    with_current_context do
      lock_transaction_signer!
      example.run
    end
  end

  it 'builds the chain while staged and queues it afterwards' do
    chain, seen_state = SpecChains::Linear.fire2(args: [node], kwargs: {})

    expect(seen_state).to eq(:staged)
    expect(chain).to be_present
    expect(chain.state).to eq('queued')
    expect(chain.size).to eq(2)
    expect(chain.user_id).to eq(User.current.id)
    expect(chain.user_session_id).to eq(UserSession.current.id)
  end

  it 'queues chains without signing when the transaction key is absent' do
    key = SysConfig.find_by!(category: 'core', name: 'transaction_key')
    original_value = key.value
    key.update_columns(value: nil)

    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})

    expect(chain).to be_present
    expect(chain.transactions.pluck(:signature)).to all(be_nil)
  ensure
    key.update_columns(value: original_value)
  end

  it 'raises for empty chains unless allow_empty is enabled' do
    expect do
      SpecChains::Empty.fire2(args: [], kwargs: {})
    end.to raise_error(RuntimeError, 'empty')
  end

  it 'returns nil for allowed empty chains' do
    chain, ret = SpecChains::AllowedEmpty.fire2(args: [], kwargs: {})

    expect(chain).to be_nil
    expect(ret).to be_nil
  end

  it 'releases acquired locks when allowed empty chains are discarded' do
    chain, = SpecChains::AllowedEmptyLocked.fire2(args: [lock_target], kwargs: {})

    expect(chain).to be_nil
    expect(
      ResourceLock.where(resource: lock_target.lock_resource_name, row_id: lock_target.id)
    ).to be_empty
  end

  it 'chains append_t dependencies linearly' do
    chain, = SpecChains::Linear.fire2(args: [node], kwargs: {})
    transactions = chain.transactions.order(:id).to_a

    expect(transactions.size).to eq(2)
    expect(transactions[0].depends_on_id).to be_nil
    expect(transactions[1].depends_on_id).to eq(transactions[0].id)
  end

  it 'anchors append_to to the named transaction instead of the tail' do
    chain, = SpecChains::Anchored.fire2(args: [node], kwargs: {})
    transactions = chain.transactions.order(:id).index_by { |t| JSON.parse(t.input).dig('input', 'tag') }

    expect(transactions.fetch('tail').depends_on_id).to eq(transactions.fetch('root').id)
    expect(transactions.fetch('branch').depends_on_id).to eq(transactions.fetch('root').id)
  end

  it 'creates a no-op transaction when append_or_noop_t(noop: true) is used' do
    chain, = SpecChains::NoopChain.fire2(args: [node], kwargs: {})
    transaction = chain.transactions.take!
    confirmations = TransactionConfirmation.where(transaction_id: transaction.id).to_a

    expect(transaction.handle).to eq(Transactions::Utils::NoOp.t_type)
    expect(transaction.queue).to eq('general')
    expect(confirmations.map(&:confirm_type)).to eq(['just_destroy_type'])
  end

  it 'preserves ordering across nested use_chain calls' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})
    transactions = chain.transactions.order(:id).to_a
    tags = transactions.to_h { |t| [JSON.parse(t.input).dig('input', 'tag'), t] }

    expect(tags.fetch('inner-1').depends_on_id).to eq(tags.fetch('outer-1').id)
    expect(tags.fetch('inner-2').depends_on_id).to eq(tags.fetch('inner-1').id)
    expect(tags.fetch('outer-2').depends_on_id).to eq(tags.fetch('inner-2').id)
  end

  it 'records concerns only on the root chain' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})

    expect(chain.transaction_chain_concerns.count).to eq(1)

    concern = chain.transaction_chain_concerns.take!
    expect(concern.class_name).to eq(lock_target.class.name)
    expect(concern.row_id).to eq(lock_target.id)
  end

  it 'deduplicates locks across nested chains' do
    chain, = SpecChains::Outer.fire2(args: [node, lock_target], kwargs: {})

    locks = ResourceLock.where(
      resource: lock_target.lock_resource_name,
      row_id: lock_target.id,
      locked_by_type: 'TransactionChain',
      locked_by_id: chain.id
    )

    expect(locks.count).to eq(1)
  end

  it 'reports included-chain context correctly' do
    outer = SpecChains::Outer.new
    inner, observed = SpecChains::ContextProbe.use_in(outer, args: [])

    expect(outer.included?).to be(false)
    expect(outer.current_chain).to eq(outer)
    expect(inner.included?).to be(true)
    expect(inner.current_chain).to eq(outer)
    expect(observed).to eq([true, outer])
  end
end
