# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Branch::Destroy do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'marks the branch confirm_destroy and appends a destroy-branch transaction' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "destroy-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    chain, = described_class.fire(branch)

    expect(tx_classes(chain)).to eq([Transactions::Storage::DestroyBranch])
    expect(branch.reload.confirmed).to eq(:confirm_destroy)
  end
end
