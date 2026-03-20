# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::DatasetTree::Destroy do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def destroy_payloads(chain)
    transactions_for(chain)
      .select { |tx| tx.handle == Transactions::Storage::DestroySnapshot.t_type }
      .map { |tx| JSON.parse(tx.input).dig('input', 'snapshot', 'name') }
  end

  it 'destroys dependent branch snapshots before the referenced parent snapshot' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "destroy-#{SecureRandom.hex(4)}")

    create_doc_branching_fixture!(dataset: dataset, backup_dip: backup)

    chain, = described_class.fire(backup.dataset_trees.take!)
    payloads = destroy_payloads(chain)

    expect(payloads.index('2014-01-04T01:00:00')).to be < payloads.index('2014-01-03T01:00:00')
    expect(payloads.index('2014-01-05T01:00:00')).to be < payloads.index('2014-01-03T01:00:00')
  end

  it 'destroys empty branches and then the tree' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "destroy-#{SecureRandom.hex(4)}")
    fixture = create_doc_branching_fixture!(dataset: dataset, backup_dip: backup)

    chain, = described_class.fire(fixture.fetch(:tree))

    expect(tx_classes(chain)).to include(
      Transactions::Storage::DestroyBranch,
      Transactions::Storage::DestroyTree
    )
    expect(fixture.fetch(:tree).reload.confirmed).to eq(:confirm_destroy)
    expect(fixture.fetch(:old_branch).reload.confirmed).to eq(:confirm_destroy)
    expect(fixture.fetch(:new_branch).reload.confirmed).to eq(:confirm_destroy)
  end
end
