# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Rotate do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def backdated_snapshot!(dataset:, dip:, name:, days_ago:)
    snap, sip = create_snapshot!(dataset: dataset, dip: dip, name: name)
    snap.update_column(:created_at, Time.now.utc - (days_ago * 86_400))
    [snap, sip]
  end

  it 'keeps the latest shared snapshot needed by open backups on primary pools' do
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool_a = create_pool!(node: SpecSeed.other_node, role: :backup)
    backup_pool_b = create_pool!(node: SpecSeed.node, role: :backup)

    dataset, primary = create_dataset_with_pool!(user: user, pool: primary_pool, name: "rotate-#{SecureRandom.hex(4)}")
    backup_a = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool_a)
    backup_b = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool_b)

    snap1, sip1 = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-1', days_ago: 3)
    snap2, sip2 = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-2', days_ago: 2)
    snap3, = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-3', days_ago: 1)

    branch_a = create_branch!(tree: create_tree!(dip: backup_a, index: 0, head: true), name: 'head-a', head: true)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup_a), branch: branch_a)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: backup_a), branch: branch_a)

    branch_b = create_branch!(tree: create_tree!(dip: backup_b, index: 0, head: true), name: 'head-b', head: true)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup_b), branch: branch_b)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: backup_b), branch: branch_b)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap3, dip: backup_b), branch: branch_b)

    primary.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)

    chain, = described_class.fire(primary)

    expect(tx_classes(chain)).to eq([Transactions::Storage::DestroySnapshot])
    expect(sip1.reload.confirmed).to eq(:confirm_destroy)
    expect(sip2.reload.confirmed).to eq(:confirmed)
  end

  it 'skips referenced snapshots on backup pools' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "rotate-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    snap1, sip1 = backdated_snapshot!(dataset: dataset, dip: backup, name: 'snap-1', days_ago: 2)
    _, sip2 = backdated_snapshot!(dataset: dataset, dip: backup, name: 'snap-2', days_ago: 1)
    sip1.update!(reference_count: 1)

    attach_snapshot_to_branch!(sip: sip1, branch: branch)
    attach_snapshot_to_branch!(sip: sip2, branch: branch)

    backup.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)

    chain, = described_class.fire(backup)

    expect(tx_classes(chain)).to include(Transactions::Storage::DestroySnapshot)
    expect(sip1.reload.confirmed).to eq(:confirmed)
    expect(sip2.reload.confirmed).to eq(:confirm_destroy)
    expect(snap1.reload.name).to eq('snap-1')
  end

  it 'schedules the oldest destroyable backup snapshots first' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "rotate-#{SecureRandom.hex(4)}")
    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    _, sip1 = backdated_snapshot!(dataset: dataset, dip: backup, name: 'snap-1', days_ago: 3)
    _, sip2 = backdated_snapshot!(dataset: dataset, dip: backup, name: 'snap-2', days_ago: 2)
    _, sip3 = backdated_snapshot!(dataset: dataset, dip: backup, name: 'snap-3', days_ago: 1)

    attach_snapshot_to_branch!(sip: sip1, branch: branch)
    attach_snapshot_to_branch!(sip: sip2, branch: branch)
    attach_snapshot_to_branch!(sip: sip3, branch: branch)

    backup.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)

    chain, = described_class.fire(backup)

    expect(tx_classes(chain)).to include(Transactions::Storage::DestroySnapshot)
    expect(sip1.reload.confirmed).to eq(:confirm_destroy)
    expect(sip2.reload.confirmed).to eq(:confirm_destroy)
    expect(sip3.reload.confirmed).to eq(:confirmed)
  end

  it 'eventually deletes branch parents only after dependents are gone' do
    backup_pool = create_pool!(node: SpecSeed.node, role: :backup)
    dataset, backup = create_dataset_with_pool!(user: user, pool: backup_pool, name: "rotate-#{SecureRandom.hex(4)}")
    create_doc_branching_fixture!(dataset: dataset, backup_dip: backup)
    backup.update!(min_snapshots: 0, max_snapshots: 0, snapshot_max_age: 0)

    pending 'branched rotation can strand snapshots because dependency metadata is incomplete'

    6.times do
      described_class.fire(backup)
    rescue RuntimeError => e
      raise unless e.message == 'empty'
    ensure
      ResourceLock.delete_all
    end

    remaining = backup.snapshot_in_pools.joins(:snapshot).order('snapshots.id').pluck('snapshots.name')
    expect(remaining).to eq([
                              '2014-01-06T01:00:00',
                              '2014-01-07T01:00:00',
                              '2014-01-08T01:00:00'
                            ])
  end

  it 'eventually releases source snapshots whose old backup copy is already gone' do
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)

    dataset, primary = create_dataset_with_pool!(user: user, pool: primary_pool, name: "rotate-#{SecureRandom.hex(4)}")
    backup = attach_dataset_to_pool!(dataset: dataset, pool: backup_pool)

    _, sip1 = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-1', days_ago: 3)
    snap2, sip2 = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-2', days_ago: 2)
    snap3, sip3 = backdated_snapshot!(dataset: dataset, dip: primary, name: 'snap-3', days_ago: 1)

    branch = create_branch!(tree: create_tree!(dip: backup, index: 0, head: true), name: 'head', head: true)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap2, dip: backup), branch: branch)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap3, dip: backup), branch: branch)

    primary.update!(min_snapshots: 1, max_snapshots: 1, snapshot_max_age: 0)

    chain, = described_class.fire(primary)

    expect(tx_classes(chain)).to eq([
                                      Transactions::Utils::NoOp,
                                      Transactions::Storage::DestroySnapshot,
                                      Transactions::Storage::DestroySnapshot
                                    ])
    expect(sip1.reload.confirmed).to eq(:confirm_destroy)
    expect(sip2.reload.confirmed).to eq(:confirm_destroy)
    expect(sip3.reload.confirmed).to eq(:confirmed)
  end
end
