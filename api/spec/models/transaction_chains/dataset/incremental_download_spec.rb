# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::IncrementalDownload do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }
  let(:primary_pool) { create_pool!(node: SpecSeed.node, role: :primary) }
  let(:backup_pool) { create_pool!(node: SpecSeed.other_node, role: :backup) }

  def create_backup_head!(dip)
    tree = create_tree!(dip: dip, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    [tree, branch]
  end

  it 'uses a common pool when both snapshots are present there' do
    dataset, primary_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      name: "inc-#{SecureRandom.hex(4)}"
    )
    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-2')

    chain, dl = described_class.fire(
      target_snapshot,
      format: :incremental_stream,
      from_snapshot: from_snapshot,
      send_mail: false
    )

    expect(dl.pool_id).to eq(primary_pool.id)
    expect(tx_classes(chain)).to eq([Transactions::Storage::DownloadSnapshot])
    expect(chain.transactions.first.queue).to eq('zfs_send')
  end

  it 'transfers the target snapshot to backup before downloading when only the base exists on backup' do
    dataset, primary_dip, backup_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "inc-#{SecureRandom.hex(4)}"
    )
    create_port_reservations!(node: backup_pool.node)
    _tree, branch = create_backup_head!(backup_dip)

    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-2')
    backup_from_sip = mirror_snapshot!(snapshot: from_snapshot, dip: backup_dip)
    attach_snapshot_to_branch!(sip: backup_from_sip, branch: branch)

    chain, dl = described_class.fire(
      target_snapshot,
      format: :incremental_stream,
      from_snapshot: from_snapshot,
      send_mail: false
    )

    expect(dl.pool_id).to eq(backup_pool.id)
    expect(tx_classes(chain)).to eq([
                                      Transactions::Storage::Recv,
                                      Transactions::Storage::Send,
                                      Transactions::Storage::RecvCheck,
                                      Transactions::Storage::DownloadSnapshot
                                    ])
  end

  it 'uses backup only when one live branch contains both incremental endpoints' do
    dataset, primary_dip, backup_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "inc-#{SecureRandom.hex(4)}"
    )
    old_branch = create_branch!(
      tree: create_tree!(dip: backup_dip, index: 0, head: false),
      name: 'old',
      head: false
    )
    head_branch = create_branch!(
      tree: create_tree!(dip: backup_dip, index: 1, head: true),
      name: 'head',
      head: true
    )

    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-2')
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: from_snapshot, dip: backup_dip),
      branch: old_branch
    )
    attach_snapshot_to_branch!(
      sip: mirror_snapshot!(snapshot: target_snapshot, dip: backup_dip),
      branch: head_branch
    )

    chain, dl = described_class.fire(
      target_snapshot,
      format: :incremental_stream,
      from_snapshot: from_snapshot,
      send_mail: false
    )

    expect(dl.pool_id).to eq(primary_pool.id)
    expect(tx_classes(chain)).to eq([Transactions::Storage::DownloadSnapshot])
  end

  it 'raises SnapshotDownloadUnavailable when no common source exists' do
    dataset, primary_dip, backup_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "inc-#{SecureRandom.hex(4)}"
    )
    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: backup_dip, name: 'snap-2')

    expect do
      described_class.fire(
        target_snapshot,
        format: :incremental_stream,
        from_snapshot: from_snapshot,
        send_mail: false
      )
    end.to raise_error(VpsAdmin::API::Exceptions::SnapshotDownloadUnavailable) { |error|
      expect(error.reason).to eq(:no_common_source)
      expect(error.snapshot_ids).to contain_exactly(from_snapshot.id, target_snapshot.id)
    }
  end

  it 'reports the transaction lock when an endpoint is pending destruction' do
    dataset, primary_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      name: "inc-locked-#{SecureRandom.hex(4)}"
    )
    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, target_sip = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-2')
    destroy_chain, = TransactionChains::SnapshotInPool::Destroy.fire(target_sip)

    expect do
      described_class.fire(
        target_snapshot,
        format: :incremental_stream,
        from_snapshot: from_snapshot,
        send_mail: false
      )
    end.to raise_error(ResourceLocked) { |error|
      expect(error.model).to eq(target_sip)
      expect(error.get_lock.locked_by).to eq(destroy_chain)
    }
  end

  it 'does not report its own source lock when the base source disappears' do
    dataset, primary_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      name: "inc-race-#{SecureRandom.hex(4)}"
    )
    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-2')
    association_calls = 0

    allow(from_snapshot).to receive(:snapshot_in_pools).and_wrap_original do |original, *args|
      association_calls += 1
      relation = original.call(*args)
      association_calls == 1 ? relation : relation.where(id: -1)
    end

    expect do
      described_class.fire(
        target_snapshot,
        format: :incremental_stream,
        from_snapshot: from_snapshot,
        send_mail: false
      )
    end.to raise_error(VpsAdmin::API::Exceptions::SnapshotDownloadUnavailable) { |error|
      expect(error.reason).to eq(:no_common_source)
    }
    expect(association_calls).to eq(2)
  end

  it 'includes both endpoints in the incremental filename' do
    root, = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      name: "user-#{SecureRandom.hex(4)}"
    )
    dataset, primary_dip = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      name: 'example',
      parent: root
    )
    from_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap:base')
    target_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap:next')

    _, dl = described_class.fire(
      target_snapshot,
      format: :incremental_stream,
      from_snapshot: from_snapshot,
      send_mail: false
    )

    expect(dl.file_name).to eq("#{dataset.full_name.tr('/', '_')}__snap-base__snap-next.inc.dat.gz")
  end
end
