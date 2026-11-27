require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::RemoveSnapshots do
  around { |example| with_current_context { example.run } }

  let(:fixture) do
    create_dataset_pair!(user: SpecSeed.user, pool: create_pool!(node: SpecSeed.node, role: :primary),
                         backup_pool: create_pool!(node: SpecSeed.other_node, role: :backup))
  end
  let(:dataset) { fixture[0] }
  let(:source) { fixture[1] }
  let(:backup) { fixture[2] }

  def scope(**options)
    described_class.new.prepare(dataset, chain: nil, recursive: false, disable_plans: true, **options)
  end

  def review(**options)
    scope(**options).inventory
  end

  def remove(**options)
    described_class.run(dataset, manifest_digest: review(**options).fetch(:manifest_digest), **options)
  end

  def branch_snapshot(branch, name, parent: nil)
    snapshot, sip = create_snapshot!(dataset:, dip: backup, name:)
    parent.snapshot_in_pool.increment!(:reference_count) if parent
    entry = attach_snapshot_to_branch!(sip:, branch:, parent_entry: parent)
    [snapshot, sip, entry]
  end

  it 'builds a deterministic complete inventory including shared locations, closed pools and empty structures' do
    backup.pool.update!(is_open: false)
    snapshot, sip = create_snapshot!(dataset:, dip: source, name: 'review-me')
    tree = create_tree!(dip: backup)
    branch = create_branch!(tree:, name: 'head')
    old_tree = create_tree!(dip: backup, index: 1, head: false)
    empty = create_branch!(tree: old_tree, name: 'empty', head: false)
    mirror = mirror_snapshot!(snapshot:, dip: backup)
    attach_snapshot_to_branch!(sip: mirror, branch:)
    attach_snapshot_to_branch!(sip: mirror, branch: empty)
    empty_tree = create_tree!(dip: backup, index: 2, head: false)

    first = review
    expect(first).to eq(review)
    expect(first.fetch(:manifest_digest)).to match(/\Av1:[0-9a-f]{64}\z/)
    manifest = first.fetch(:manifest)
    expect(manifest[:counts]).to include(snapshots: 1, snapshot_locations: 3, trees: 3, branches: 2)
    expect(manifest[:snapshot_locations].map { |row| row[:snapshot_in_pool_id] }).to contain_exactly(sip.id, mirror.id, mirror.id)
    expect(manifest[:copies].find { |row| row[:id] == backup.id }[:pool_open]).to be(false)
    expect(manifest[:trees].map { |row| row[:id] }).to include(empty_tree.id)
  end

  it 'removes backup branch leaves before their origins with unequal nested fanout, and source snapshots last' do
    backup
    tree = create_tree!(dip: backup)
    a, b, c, d = %w[a b c d].map { |name| create_branch!(tree:, name:, head: name == 'a') }
    _, origin_sip, origin = branch_snapshot(a, 'origin')
    _, middle_sip, middle = branch_snapshot(b, 'middle', parent: origin)
    branch_snapshot(c, 'leaf-c', parent: middle)
    branch_snapshot(d, 'leaf-d', parent: middle)
    source_snapshot, = create_snapshot!(dataset:, dip: source, name: 'source-only')
    chain, = remove
    transactions = transactions_for(chain)
    params = transactions.map { |tx| [tx.handle, JSON.parse(tx.input).fetch('input')] }
    snapshot_delete = ->(id) { params.index { |handle, input| handle == 5212 && input.dig('snapshot', 'id') == id } }
    branch_delete = ->(branch) { params.index { |handle, input| handle == 5207 && input['branch'] == branch.full_name } }
    expect(branch_delete.call(c)).to be < snapshot_delete.call(middle_sip.snapshot_id)
    expect(branch_delete.call(d)).to be < snapshot_delete.call(middle_sip.snapshot_id)
    expect(branch_delete.call(b)).to be < snapshot_delete.call(origin_sip.snapshot_id)
    expect(snapshot_delete.call(source_snapshot.id)).to be > branch_delete.call(a)
    expect(transactions.map(&:reversible)).to all(eq('not_reversible'))
    expect(backup.reload.confirmed).to eq(:confirmed)
    expect(source.reload.confirmed).to eq(:confirmed)
  end

  it 'removes shared memberships exactly once per location, then empty branches and trees' do
    backup
    snapshot, = create_snapshot!(dataset:, dip: source)
    mirrored = mirror_snapshot!(snapshot:, dip: backup)
    trees = 2.times.map { |i| create_tree!(dip: backup, index: i, head: i == 0) }
    trees.each { |tree| attach_snapshot_to_branch!(sip: mirrored, branch: create_branch!(tree:, name: "branch-#{tree.id}")) }
    empty_tree = create_tree!(dip: backup, index: 2, head: false)
    empty_branch = create_branch!(tree: empty_tree, name: 'empty')
    chain, = remove
    expect(tx_classes(chain).count(Transactions::Storage::DestroySnapshot)).to eq(3)
    expect(empty_branch.reload.confirmed).to eq(:confirm_destroy)
    expect(empty_tree.reload.confirmed).to eq(:confirm_destroy)
    expect(snapshot.reload.confirmed).to eq(:confirm_destroy)
  end

  it 'disables plans by default while retaining unrelated shared group members' do
    backup
    _, plan = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
    membership = source.add_plan(plan)
    other, other_source = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: "shared-#{SecureRandom.hex(4)}")
    attach_dataset_to_pool!(dataset: other, pool: backup.pool)
    other_source.add_plan(plan)
    other_group = other_source.group_snapshots.first!
    chain, = remove
    confirmations = confirmations_for(chain).where(confirm_type: :just_destroy_type)
    deleted = confirmations.map(&:class_name)
    expect(deleted).to include('DatasetInPoolPlan', 'GroupSnapshot', 'DatasetAction', 'RepeatableTask')
    expect(membership).not_to be_nil
    expect(review[:manifest][:plans].first[:action]).to eq('remove')
    expect(confirmations.select { |row| row.class_name == 'GroupSnapshot' }.map(&:row_pks)).not_to include('id' => other_group.id)
    expect(other_group.reload).to be_persisted
  end

  it 'retains plans when explicitly requested, and still produces an ordinary irreversible empty task' do
    backup
    _, plan = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
    source.add_plan(plan)
    chain, = remove(disable_plans: false)
    expect(confirmations_for(chain)).to be_empty
    expect(tx_classes(chain)).to eq([Transactions::Utils::NoOp])
    expect(chain).to be_queued
    expect(source).to be_locked
  end

  %i[snapshot copy empty_tree plan descendant option origin].each do |change|
    it "rejects a stale #{change} before any mutation or queued chain" do
      backup
      digest = review.fetch(:manifest_digest)
      options = {}
      case change
      when :snapshot then create_snapshot!(dataset:, dip: source)
      when :copy then attach_dataset_to_pool!(dataset:, pool: create_pool!(node: SpecSeed.node, role: :backup))
      when :empty_tree then create_tree!(dip: backup)
      when :plan
        _, plan = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
        source.add_plan(plan)
      when :descendant
        child, = create_dataset_with_pool!(user: dataset.user, pool: source.pool, name: "child-#{SecureRandom.hex(4)}")
        child.update!(parent: dataset)
        options[:recursive] = true
      when :option then options[:disable_plans] = false
      when :origin
        tree = create_tree!(dip: backup)
        branch_snapshot(create_branch!(tree:, name: 'origin'), 'origin')
      end
      counts = [TransactionChain.count, Transaction.count, ResourceLock.count]
      expect { described_class.run(dataset, manifest_digest: digest, **options) }.to raise_error(described_class::StalePreview)
      expect([TransactionChain.count, Transaction.count, ResourceLock.count]).to eq(counts)
      expect(SnapshotInPool.where(dataset_in_pool: [source, backup]).pluck(:confirmed)).to all(eq(1))
    end
  end

  %i[reference inactive_clone pending orphan cycle foreign_origin unavailable automation].each do |unsafe|
    it "rejects #{unsafe} backup state before preparing work" do
      backup
      tree = create_tree!(dip: backup)
      branch = create_branch!(tree:, name: 'history')
      _, sip, entry = branch_snapshot(branch, 'protected')
      case unsafe
      when :reference then sip.update!(reference_count: 1)
      when :inactive_clone
        SnapshotInPoolClone.create!(snapshot_in_pool: sip, user_namespace_map: create_user_namespace_map!(user: SpecSeed.user),
                                    name: 'protected.snapshot', state: :inactive)
      when :pending then entry.update!(confirmed: SnapshotInPoolInBranch.confirmed(:confirm_create))
      when :orphan then entry.delete
      when :cycle then entry.update!(snapshot_in_pool_in_branch_id: entry.id)
      when :foreign_origin
        other, other_dip = create_dataset_with_pool!(user: SpecSeed.other_user, pool: backup.pool, name: "foreign-#{SecureRandom.hex(4)}")
        foreign_tree = create_tree!(dip: other_dip)
        foreign_branch = create_branch!(tree: foreign_tree, name: 'foreign')
        _, foreign_sip = create_snapshot!(dataset: other, dip: other_dip)
        foreign_entry = attach_snapshot_to_branch!(sip: foreign_sip, branch: foreign_branch)
        entry.update!(snapshot_in_pool_in_branch: foreign_entry)
      when :unavailable then backup.pool.update!(state: :faulted)
      when :automation then DatasetAction.create!(action: :snapshot, src_dataset_in_pool: backup)
      end
      expect { review }.to raise_error(described_class::Rejected)
      expect(sip.reload.confirmed).to eq(:confirmed)
    end
  end
end
