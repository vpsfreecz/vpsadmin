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

  it 'signs activity handle 5291 on the old storage queue without a mutation intent' do
    request = {
      protocol_version: 1, request_uuid: SecureRandom.uuid,
      attempt_uuid: SecureRandom.uuid, nonce: SecureRandom.hex(32),
      node_id: SpecSeed.node.id,
      freeze_epoch: StorageFreezeControl.singleton!.epoch,
      deadline: (Time.now.utc + 60).iso8601(6),
      claims: []
    }
    chain, = TransactionChains::Storage::ActivityProbe.fire(request)
    transaction = chain.transactions.sole.reload

    expect(transaction).to have_attributes(handle: 5291, queue: 'storage')
    expect(transaction.signature).not_to be_empty
    expect(StorageMutationIntent.where(transaction_id: transaction.id)).to be_empty
    expect(JSON.parse(transaction.input).fetch('input')).to eq(request.as_json)
  end
end
