# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::RemoveDownload do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_download!(snapshot:, pool:)
    SnapshotDownload.create!(
      user: user,
      snapshot: snapshot,
      from_snapshot: nil,
      pool: pool,
      secret_key: SecureRandom.hex(16),
      file_name: 'download.dat.gz',
      confirmed: SnapshotDownload.confirmed(:confirmed),
      format: :stream,
      object_state: :active,
      expiration_date: Time.now + 7.days
    )
  end

  it 'marks the download for destroy, queues cleanup, and clears the snapshot link on confirmation' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "download-#{SecureRandom.hex(4)}")
    snapshot, = create_snapshot!(dataset: dataset, dip: dip, name: 'snap-1')
    download = create_download!(snapshot: snapshot, pool: pool)
    snapshot.update!(snapshot_download_id: download.id)

    chain, = described_class.fire(download)
    confirmations = confirmations_for(chain)

    expect(download.reload.confirmed).to eq(:confirm_destroy)
    expect(tx_classes(chain)).to eq([Transactions::Storage::RemoveDownload])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['SnapshotDownload', download.id]
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['SnapshotDownload', download.id]
    )
    expect(
      confirmations.find { |row| row.class_name == 'Snapshot' && row.row_pks == { 'id' => snapshot.id } }
                 &.attr_changes
    ).to eq('snapshot_download_id' => nil)
    expect(
      confirmations.find { |row| row.class_name == 'SnapshotDownload' && row.row_pks == { 'id' => download.id } }
                 &.confirm_type
    ).to eq('destroy_type')
  end
end
