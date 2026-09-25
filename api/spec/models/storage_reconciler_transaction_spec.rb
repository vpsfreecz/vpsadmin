# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Transactions::Storage::Inventory do
  around do |example|
    with_current_context do
      unlock_transaction_signer!
      example.run
    ensure
      lock_transaction_signer!
    end
  end

  it 'persists a queue understood by old NodeCtld versions' do
    chain, = TransactionChains::Storage::Inventory.fire({ node_id: SpecSeed.node.id })
    transaction = chain.transactions.sole.reload

    expect(transaction.handle).to eq(5290)
    expect(transaction.queue).to eq('storage')
  end

  it 'rejects the new execution queue as a persisted queue name' do
    transaction = Transaction.new(queue: 'inventory')
    transaction.valid?

    expect(transaction.errors.details.fetch(:queue)).to include(a_hash_including(error: :inclusion))
  end
end
