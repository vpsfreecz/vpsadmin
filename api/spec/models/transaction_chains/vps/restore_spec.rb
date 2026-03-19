# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Restore do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  it 'stops the VPS before rollback, starts it afterwards, and logs a restore event' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "restore-#{SecureRandom.hex(4)}")
    vps = create_vps_for_dataset!(user: user, node: pool.node, dataset_in_pool: dip)
    snap1, = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    create_snapshot!(dataset: dataset, dip: dip, name: 'snap-2')

    chain, = described_class.fire(vps, snap1)

    transactions = transactions_for(chain)
    stop_tx = transactions[0]
    start_tx = transactions[2]

    expect(tx_classes(chain)).to eq([
                                      Transactions::Vps::Stop,
                                      Transactions::Storage::Rollback,
                                      Transactions::Vps::Start,
                                      Transactions::Utils::NoOp
                                    ])
    expect(JSON.parse(stop_tx.input).dig('input', 'kill')).to be(true)
    expect(start_tx.reversible).to eq('keep_going')
    expect(ObjectHistory.where(tracked_object: vps, event_type: 'restore').count).to eq(1)
  end

  it 'includes prepare/apply rollback and backup branching when restoring from backup' do
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: primary_pool.node)
    create_port_reservations!(node: backup_pool.node)

    dataset, primary, backup = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "restore-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: primary_pool.node, dataset_in_pool: primary)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup), branch: branch)

    snap2 = Snapshot.create!(
      dataset: dataset,
      name: 'snap-2',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    backup_sip2 = mirror_snapshot!(snapshot: snap2, dip: backup)
    entry2 = attach_snapshot_to_branch!(sip: backup_sip2, branch: branch)

    snap3 = Snapshot.create!(
      dataset: dataset,
      name: 'snap-3',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: snap3, dip: backup),
      branch: branch,
      parent_entry: entry2
    )

    chain, = described_class.fire(vps, snap2)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::PrepareRollback,
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Vps::Stop,
                                      Transactions::Storage::ApplyRollback,
                                      Transactions::Vps::Start,
                                      Transactions::Storage::BranchDataset,
                                      Transactions::Utils::NoOp
                                    ])
  end
end
