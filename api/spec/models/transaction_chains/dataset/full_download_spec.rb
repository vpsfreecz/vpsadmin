# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::FullDownload do
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

  def lock_rows(chain)
    chain.locks.map { |lock| [lock.resource, lock.row_id] }
  end

  it 'prefers the backup copy when both primary and backup copies exist' do
    dataset, primary_dip, backup_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "download-#{SecureRandom.hex(4)}"
    )
    _tree, branch = create_backup_head!(backup_dip)
    snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')
    backup_sip = mirror_snapshot!(snapshot: snapshot, dip: backup_dip)
    attach_snapshot_to_branch!(sip: backup_sip, branch: branch)

    chain, dl = described_class.fire(snapshot, format: :stream, send_mail: false)
    payload = tx_payloads(chain).first

    expect(dl.pool_id).to eq(backup_pool.id)
    expect(tx_classes(chain)).to eq([Transactions::Storage::DownloadSnapshot])
    expect(chain.transactions.first.queue).to eq('zfs_send')
    expect(lock_rows(chain)).to include(
      ['SnapshotInPool', backup_sip.id],
      ['DatasetInPool', backup_dip.id]
    )
    expect(
      confirmations_for(chain).find { |row| row.class_name == 'Snapshot' && row.row_pks == { 'id' => snapshot.id } }
                               &.attr_changes
    ).to eq('snapshot_download_id' => dl.id)
    expect(payload).to include(
      'pool_fs' => backup_pool.filesystem,
      'dataset_name' => dataset.full_name,
      'snapshot' => 'snap-1',
      'format' => 'stream',
      'tree' => 'tree.0',
      'branch' => 'branch-head.0'
    )
  end

  it 'falls back to the primary copy when no backup copy exists' do
    dataset, primary_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      name: "download-#{SecureRandom.hex(4)}"
    )
    snapshot, primary_sip = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')

    chain, dl = described_class.fire(snapshot, format: :stream, send_mail: false)

    expect(dl.pool_id).to eq(primary_pool.id)
    expect(tx_classes(chain)).to eq([Transactions::Storage::DownloadSnapshot])
    expect(chain.transactions.first.queue).to eq('zfs_send')
    expect(lock_rows(chain)).to include(
      ['SnapshotInPool', primary_sip.id],
      ['DatasetInPool', primary_dip.id]
    )
  end

  it 'uses the general queue for archive downloads' do
    dataset, primary_dip = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      name: "archive-#{SecureRandom.hex(4)}"
    )
    snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: 'snap-1')

    chain, = described_class.fire(snapshot, format: :archive, send_mail: false)

    expect(tx_classes(chain)).to eq([Transactions::Storage::DownloadSnapshot])
    expect(chain.transactions.first.queue).to eq('general')
  end

  it 'raises when the snapshot exists nowhere' do
    dataset, = create_dataset_with_pool!(
      user: user,
      pool: primary_pool,
      name: "missing-#{SecureRandom.hex(4)}"
    )
    snapshot = Snapshot.create!(
      dataset: dataset,
      name: 'snap-missing',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )

    expect do
      described_class.fire(snapshot, format: :stream, send_mail: false)
    end.to raise_error(RuntimeError, 'snapshot is nowhere to be found!')
  end

  it 'builds stable archive and stream file names' do
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
    archive_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: '2024-01-01T00:00:00')
    stream_snapshot, = create_snapshot!(dataset: dataset, dip: primary_dip, name: '2024-01-02T00:00:00')

    archive_chain, archive_download = described_class.fire(archive_snapshot, format: :archive, send_mail: false)
    archive_chain.release_locks
    _, stream_download = described_class.fire(stream_snapshot, format: :stream, send_mail: false)

    prefix = "#{dataset.full_name.tr('/', '_')}__"

    expect(archive_download.file_name).to eq("#{prefix}2024-01-01T00-00-00.tar.gz")
    expect(stream_download.file_name).to eq("#{prefix}2024-01-02T00-00-00.dat.gz")
  end
end
