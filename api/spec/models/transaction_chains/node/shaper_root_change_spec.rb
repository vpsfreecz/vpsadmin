# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Node::ShaperRootChange do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  it 'locks the node, appends root shaper update, and confirms original limits' do
    node = SpecSeed.node
    original_max_tx = node.max_tx
    original_max_rx = node.max_rx
    node.assign_attributes(
      max_tx: original_max_tx + 1024,
      max_rx: original_max_rx + 2048
    )

    chain, = described_class.fire(node)

    expect(tx_classes(chain)).to eq([Transactions::Vps::ShaperRootChange])
    expect(tx_payload(chain, Transactions::Vps::ShaperRootChange)).to include(
      'max_tx' => original_max_tx + 1024,
      'max_rx' => original_max_rx + 2048,
      'original' => {
        'max_tx' => original_max_tx,
        'max_rx' => original_max_rx
      }
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Node', node.id])
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Node' &&
        row.row_pks == { 'id' => node.id } &&
        row.confirm_type == 'edit_before_type' &&
        row.attr_changes == {
          'max_tx' => original_max_tx,
          'max_rx' => original_max_rx
        }
    end).to be(true)
  end
end
