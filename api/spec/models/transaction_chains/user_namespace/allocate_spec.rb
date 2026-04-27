# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::UserNamespace::Allocate do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before { ensure_available_node_status!(SpecSeed.node) }

  it 'allocates a contiguous block range and confirms the local DB changes' do
    ensure_user_namespace_blocks!(count: 4)
    user = create_lifecycle_user!

    chain, userns = described_class.fire(user, 2)
    blocks = UserNamespaceBlock.where(user_namespace: userns).order(:index).to_a
    confirmations = confirmations_for(chain)

    expect(userns).to be_persisted
    expect(userns.user).to eq(user)
    expect(userns.block_count).to eq(2)
    expect(blocks.size).to eq(2)
    expect(blocks.map(&:index)).to eq((blocks.first.index..blocks.last.index).to_a)
    expect(userns.offset).to eq(blocks.first.offset)
    expect(userns.size).to eq(blocks.sum(&:size))
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])

    expect(confirmations.any? do |row|
      row.class_name == 'UserNamespace' &&
        row.row_pks == { 'id' => userns.id } &&
        row.confirm_type == 'just_create_type'
    end).to be(true)
    blocks.each do |block|
      expect(confirmations.any? do |row|
        row.class_name == 'UserNamespaceBlock' &&
          row.row_pks == { 'id' => block.id } &&
          row.confirm_type == 'edit_before_type' &&
          row.attr_changes == { 'user_namespace_id' => nil }
      end).to be(true)
    end
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['UserNamespace', userns.id],
      ['UserNamespaceBlock', blocks.first.id],
      ['UserNamespaceBlock', blocks.last.id]
    )
  end
end
