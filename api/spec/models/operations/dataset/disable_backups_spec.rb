# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::DisableBackups do
  around { |example| with_current_context { example.run } }

  let(:fixture) do
    create_dataset_pair!(user: SpecSeed.user, pool: create_pool!(node: SpecSeed.node, role: :primary),
                         backup_pool: create_pool!(node: SpecSeed.other_node, role: :backup))
  end
  let(:dataset) { fixture[0] }
  let(:source) { fixture[1] }
  let(:target) { fixture[2] }
  let(:rejected) { described_class::Rejected }

  before do
    target
    create_port_reservations!(node: target.pool.node)
  end

  def snapshot(name = nil)
    create_snapshot!(dataset: dataset, dip: source, name: name)
  end

  def cover(snap, destination = target, head: true)
    tree = destination.dataset_trees.first || create_tree!(dip: destination, head: head)
    branch = tree.branches.first || create_branch!(tree: tree, name: 'history', head: head)
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap, dip: destination), branch: branch)
  end

  def assign_plan
    _, env = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
    source.add_plan(env)
  end

  def delete_confirmations(chain)
    confirmations_for(chain).where(confirm_type: :just_destroy_type).map { |row| [row.class_name, row.row_pks.fetch('id')] }
  end

  def expect_irreversible_suffix(chain)
    transactions = transactions_for(chain)
    boundary = transactions.index { |tx| tx.reversible == 'not_reversible' }
    expect(boundary).not_to be_nil
    expect(transactions[boundary..].map(&:reversible)).to all(eq('not_reversible'))
    expect(transactions.map(&:reversible)).not_to include('keep_going')
    transactions[boundary..]
  end

  it 'returns one queued chain for empty planless work without a backup target' do
    target.destroy!
    chain, = described_class.run(dataset)
    expect(chain).to be_a(TransactionChains::Dataset::DisableBackups)
    expect(chain).to be_queued
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(source).to be_locked
    expect_irreversible_suffix(chain)
  end

  it 'plans ordinary transfers and source destruction in the same chain without a new snapshot' do
    plan = assign_plan
    snapshot('manual-1')
    snapshot('manual-2')
    count = Snapshot.count
    chain, = described_class.run(dataset)
    expect(chain).to be_a(TransactionChains::Dataset::DisableBackups)
    expect(Snapshot.count).to eq(count)
    expect(source.snapshot_in_pools.map(&:confirmed)).to all(eq(:confirm_destroy))
    expect(plan.reload).to be_present # Ordinary confirmation has not run yet.
    expect(delete_confirmations(chain)).to include(['DatasetInPoolPlan', plan.id])
    types = tx_classes(chain)
    expect(types).to include(Transactions::Storage::Send, Transactions::Storage::RecvCheck, Transactions::Storage::DestroySnapshot)
    first_destroy = types.index(Transactions::Storage::DestroySnapshot)
    expect(types.each_index.select { |i| types[i] == Transactions::Storage::RecvCheck }.max).to be < first_destroy
    expect_irreversible_suffix(chain)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id).uniq.size).to eq(chain.transaction_chain_concerns.count)
  end

  it 'checks every newly copied snapshot at its branch before every cleanup transaction' do
    3.times { |i| snapshot("snapshot-#{i}") }
    other = attach_dataset_to_pool!(dataset: dataset, pool: create_pool!(node: target.pool.node, role: :backup))
    chain, = described_class.run(dataset)
    transactions = transactions_for(chain)
    checks = transactions.select { |tx| tx.handle == Transactions::Storage::RecvCheck.t_type }
    expect(checks.size).to eq(6) # Initial/tip checks are reused, the middle gets an extra check.
    [target, other].each do |destination|
      params = checks.map { |tx| JSON.parse(tx.input).fetch('input') }
                     .select { |p| p.fetch('dst_pool_fs') == destination.pool.filesystem }
      expect(params.map { |p| p.dig('snapshot', 'id') }).to match_array(source.snapshot_in_pools.pluck(:snapshot_id))
      expect(params.map { |p| [p['tree'], p['branch']] }.uniq.size).to eq(1)
      expect(params).to all(include('tree' => 'tree.0'))
    end
    suffix = expect_irreversible_suffix(chain)
    expect(checks.map(&:id).max).to be < suffix.first.id
  end

  it 'uses existing receive checks after local synchronous sends too' do
    target.pool.update!(node: source.pool.node)
    create_port_reservations!(node: source.pool.node)
    3.times { |i| snapshot("local-#{i}") }
    chain, = described_class.run(dataset)
    types = tx_classes(chain)
    expect(types).to include(Transactions::Storage::LocalSend)
    expect(types).not_to include(Transactions::Storage::Send)
    expect(types.count(Transactions::Storage::RecvCheck)).to eq(3)
    expect(types.rindex(Transactions::Storage::RecvCheck)).to be < types.index(Transactions::Storage::DestroySnapshot)
  end

  %w[oldest middle].each do |gap|
    it "rejects a missing #{gap} snapshot below the head instead of forcing a new tree" do
      plan = assign_plan
      first, = snapshot('oldest')
      middle, = snapshot('middle')
      last, = snapshot('latest')
      cover(first) unless gap == 'oldest'
      cover(middle) unless gap == 'middle'
      cover(last)
      expect { described_class.run(dataset) }.to raise_error(rejected, /ordinary transfer cannot preserve snapshot .* backup/)
      expect(TransactionChains::Dataset::DisableBackups.count).to eq(0)
      expect(source.snapshot_in_pools.map(&:confirmed)).to all(eq(:confirmed))
      expect(plan.reload).to be_present
      expect(target.dataset_trees.count).to eq(1)
      expect(target.dataset_trees.first.head).to be(true)
    end
  end

  it 'rolls back earlier target planning when a later target has an old gap' do
    other = attach_dataset_to_pool!(dataset: dataset, pool: create_pool!(node: target.pool.node, role: :backup))
    snapshot('oldest')
    last, = snapshot('newest')
    cover(last, other)
    expect { described_class.run(dataset) }.to raise_error(rejected, /ordinary transfer cannot preserve/)
    expect(target.dataset_trees).to be_empty
    expect(target.snapshot_in_pools).to be_empty
    expect(source.snapshot_in_pools.map(&:confirmed)).to all(eq(:confirmed))
  end

  it 'uses the unchanged ordinary full path when no common head history exists' do
    snapshot('source')
    old, old_copy = create_snapshot!(dataset: dataset, dip: target, name: 'old-history')
    tree = create_tree!(dip: target)
    attach_snapshot_to_branch!(sip: old_copy, branch: create_branch!(tree: tree, name: 'old'))
    chain, = described_class.run(dataset)
    expect(target.dataset_trees.count).to eq(2)
    expect(tx_classes(chain)).to include(Transactions::Storage::CreateTree)
    expect(old.reload).to be_present
    expect_irreversible_suffix(chain)
  end

  it 'counts confirmed retained non-head coverage and does not reject backup-only references' do
    snap, = snapshot
    entry = cover(snap, head: false)
    entry.snapshot_in_pool.update!(reference_count: 9)
    chain, = described_class.run(dataset)
    expect(tx_classes(chain)).not_to include(Transactions::Storage::Send, Transactions::Storage::LocalSend)
    expect(tx_classes(chain)).to include(Transactions::Storage::DestroySnapshot)
  end

  %i[copy membership branch tree target].each do |pending|
    it "rejects an unrelated pending #{pending} before modification" do
      snap, = snapshot
      entry = cover(snap)
      object = { copy: entry.snapshot_in_pool, membership: entry, branch: entry.branch,
                 tree: entry.branch.dataset_tree, target: target }.fetch(pending)
      object.update!(confirmed: 0)
      expect { described_class.run(dataset) }.to raise_error(rejected, /pending/)
      expect(source.snapshot_in_pools.first).to be_confirmed
    end
  end

  %w[SnapshotInPool SnapshotInPoolInBranch Branch DatasetTree].each do |klass|
    it "does not count a pending #{klass} without this chain's create confirmation" do
      snapshot
      allow(TransactionChains::Dataset::Transfer).to receive(:use_in).and_wrap_original do |original, chain, opts|
        result = original.call(chain, opts)
        TransactionConfirmation.joins(:parent_transaction).where(
          transactions: { transaction_chain_id: chain.current_chain.id }, class_name: klass, confirm_type: :create_type
        ).delete_all
        result
      end
      expect { described_class.run(dataset) }.to raise_error(rejected, /ordinary transfer cannot preserve/)
      expect(source.snapshot_in_pools.first).to be_confirmed
      expect(target.snapshot_in_pools).to be_empty
    end
  end

  it 'rejects a nonempty source with no open target, but permits an explicit opt-out' do
    plan = assign_plan
    snapshot
    target.pool.update!(is_open: false)
    tree = create_tree!(dip: target)
    branch = create_branch!(tree: tree, name: 'closed')
    expect { described_class.run(dataset) }.to raise_error(rejected, /no open backup/)
    expect(plan.reload).to be_present
    chain, = described_class.run(dataset, backup_first: false)
    expect(tx_classes(chain)).not_to include(Transactions::Storage::Send)
    expect(confirmations_for(chain).map { |row| [row.class_name, row.row_pks, row.attr_changes] }).to include(
      ['DatasetTree', { 'id' => tree.id }, { 'head' => 0 }], ['Branch', { 'id' => branch.id }, { 'head' => 0 }]
    )
    expect(tree.reload.head).to be(true) # Heads change only through ordinary confirmations.
    expect_irreversible_suffix(chain)
  end

  [false, true].each do |empty|
    it "allows unavailable backup metadata when preservation is unnecessary (empty #{empty})" do
      snapshot unless empty
      target.pool.node.update!(active: false)
      chain, = described_class.run(dataset, backup_first: empty)
      expect(tx_classes(chain)).not_to include(Transactions::Storage::Send)
      expect(transactions_for(chain).map(&:node_id).uniq).to eq([source.pool.node_id])
    end
  end

  it 'requires target availability for nonempty backup-first even when coverage already exists' do
    snap, = snapshot
    cover(snap)
    target.pool.node.update!(active: false)
    expect { described_class.run(dataset) }.to raise_error(rejected, /unavailable/)
    expect(source.snapshot_in_pools.first).to be_confirmed
  end

  it 'rejects a protected recursive member before any source destruction is staged' do
    assign_plan
    snapshot
    child, child_source = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: 'child', parent: dataset)
    create_snapshot!(dataset: child, dip: child_source, reference_count: 1)
    expect { described_class.run(dataset, recursive: true, backup_first: false) }.to raise_error(rejected, /in use/)
    expect(source.snapshot_in_pools.first).to be_confirmed
    expect(source.dataset_in_pool_plans.count).to eq(1)
  end

  %i[subtree source].each do |change|
    it "rejects #{change} changes completed before resource acquisition" do
      operation = described_class.new
      allow(described_class).to receive(:new).and_return(operation)
      changed = false
      allow(operation).to receive(:acquire).and_wrap_original do |original, object|
        if !changed && object.is_a?(DatasetInPool) && object.id == source.id
          changed = true
          if change == :subtree
            create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: 'new-child', parent: dataset)
          else
            source.update!(pool: create_pool!(node: source.pool.node, role: :primary))
          end
        end
        original.call(object)
      end

      expect do
        described_class.run(dataset, recursive: true, backup_first: false)
      end.to raise_error(rejected, /scope changed/)
      expect(TransactionChains::Dataset::DisableBackups.count).to eq(0)
    end
  end

  it 'orders all recursive transfers and checks before metadata and every source deletion' do
    3.times { |i| snapshot("root-#{i}") }
    child, child_source = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: 'child', parent: dataset)
    child_target = attach_dataset_to_pool!(dataset: child, pool: target.pool)
    create_snapshot!(dataset: child, dip: child_source)
    chain, = described_class.run(dataset, recursive: true)
    suffix = expect_irreversible_suffix(chain)
    checks = transactions_for(chain).select { |tx| tx.handle == Transactions::Storage::RecvCheck.t_type }
    expect(checks.size).to eq(4)
    expect(checks.map(&:id).max).to be < suffix.first.id
    expect(child_target.snapshot_in_pools.count).to eq(1)
    expect(tx_classes(chain).count(Transactions::Storage::DestroySnapshot)).to eq(4)
  end

  it 'rejects a recursive source without a destination and rolls back the entire construction' do
    snapshot
    child, child_source = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: 'child', parent: dataset)
    create_snapshot!(dataset: child, dip: child_source)
    expect { described_class.run(dataset, recursive: true) }.to raise_error(rejected, /no open backup/)
    expect(target.snapshot_in_pools).to be_empty
    expect(TransactionChains::Dataset::DisableBackups.count).to eq(0)
  end

  it 'retains a shared group action/task when an unrelated dataset joins during the accepted chain' do
    plan = assign_plan
    member = source.group_snapshots.first
    action = member.dataset_action
    task = RepeatableTask.find_for!(action)
    chain, = described_class.run(dataset, backup_first: false)
    other, other_source = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: 'independent')
    attach_dataset_to_pool!(dataset: other, pool: target.pool)
    other_source.add_plan(plan.environment_dataset_plan)
    removed = delete_confirmations(chain)
    expect(removed).to include(['GroupSnapshot', member.id], ['DatasetInPoolPlan', plan.id])
    expect(removed).not_to include(['DatasetAction', action.id], ['RepeatableTask', task.id],
                                   ['GroupSnapshot', other_source.group_snapshots.first.id])
    expect(action.reload.group_snapshots.count).to eq(2)
  end

  it 'rejects manually scheduled work and conflicting locks without removing plans' do
    assign_plan
    DatasetAction.create!(src_dataset_in_pool: source, action: :snapshot)
    expect { described_class.run(dataset) }.to raise_error(rejected, /non-plan automation/)
    source.acquire_lock
    expect { described_class.run(dataset) }.to raise_error(ResourceLocked)
    expect(source.dataset_in_pool_plans.count).to eq(1)
  end

  it 'rejects a wrong action type even when it names a selected plan' do
    plan = assign_plan
    DatasetAction.create!(src_dataset_in_pool: source, action: :snapshot, dataset_in_pool_plan: plan)
    expect { described_class.run(dataset) }.to raise_error(rejected, /non-plan automation/)
    expect(plan.reload).to be_present
  end

  it 'rejects incoming automation and inconsistent group membership' do
    plan = assign_plan
    action = DatasetAction.create!(dst_dataset_in_pool: source, action: :transfer)
    expect { described_class.run(dataset) }.to raise_error(rejected, /incoming automation/)
    action.destroy!
    source.group_snapshots.first.dataset_action.update!(action: :snapshot)
    expect { described_class.run(dataset) }.to raise_error(rejected, /group automation/)
    expect(plan.reload).to be_present
  end

  it 'makes orphan-download helpers irreversible together with unbacked source destruction' do
    snapshot
    chain, = described_class.run(dataset, backup_first: false)
    suffix = expect_irreversible_suffix(chain)
    expect(suffix.count { |tx| tx.handle == Transactions::Utils::NoOp.t_type }).to be >= 2
    expect(tx_classes(chain)).to include(Transactions::Storage::DestroySnapshot)
  end

  it 'rolls back all intent and newly planned backup rows if cleanup construction fails' do
    plan = assign_plan
    snapshot
    allow(TransactionChains::SnapshotInPool::Destroy).to receive(:use_in).and_raise('construction failed')
    expect { described_class.run(dataset) }.to raise_error('construction failed')
    expect(plan.reload).to be_present
    expect(source.snapshot_in_pools.first).to be_confirmed
    expect(target.dataset_trees).to be_empty
  end
end
