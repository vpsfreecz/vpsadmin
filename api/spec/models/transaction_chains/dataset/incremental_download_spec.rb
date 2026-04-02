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

  it 'raises when neither a common pool nor a backup base snapshot exists' do
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
    end.to raise_error(ActiveRecord::RecordNotFound)
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
