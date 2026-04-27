# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::UserNamespace::Free do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before { ensure_available_node_status!(SpecSeed.node) }

  it 'frees associated blocks, destroys maps, and destroys the namespace in a local NoOp' do
    userns, map = create_user_namespace_with_map!(user: create_lifecycle_user!, block_count: 2)
    attach_blocks_to_user_namespace!(userns)
    blocks = userns.user_namespace_blocks.order(:index).to_a

    chain, = described_class.fire(userns)
    confirmations = confirmations_for(chain)

    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(confirmations.any? do |row|
      row.class_name == 'UserNamespaceMap' &&
        row.row_pks == { 'id' => map.id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)
    blocks.each do |block|
      expect(confirmations.any? do |row|
        row.class_name == 'UserNamespaceBlock' &&
          row.row_pks == { 'id' => block.id } &&
          row.confirm_type == 'edit_after_type' &&
          row.attr_changes == { 'user_namespace_id' => nil }
      end).to be(true)
    end
    expect(confirmations.any? do |row|
      row.class_name == 'UserNamespace' &&
        row.row_pks == { 'id' => userns.id } &&
        row.confirm_type == 'just_destroy_type'
    end).to be(true)
  end
end
