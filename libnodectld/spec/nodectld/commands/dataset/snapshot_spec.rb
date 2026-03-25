# frozen_string_literal: true

require 'spec_helper'
require 'time'
require 'nodectld/dataset'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/snapshot'

RSpec.describe NodeCtld::Commands::Dataset::Snapshot do
  let(:driver) { build_storage_driver }

  it 'stores the confirmed snapshot name and timestamp on save' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'snapshot_id' => 42
    )

    dataset = instance_double(NodeCtld::Dataset)
    allow(NodeCtld::Dataset).to receive(:new).and_return(dataset)
    allow(dataset).to receive(:snapshot)
      .with('tank/ct', '101')
      .and_return(['snap-1', Time.utc(2024, 1, 1, 0, 0, 0)])

    db = instance_double(NodeCtld::Db)
    allow(db).to receive(:prepared)

    expect(cmd.exec).to eq(ret: :ok)
    cmd.on_save(db)

    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ?, created_at = ? WHERE id = ?',
      'snap-1',
      '2024-01-01 00:00:00',
      42
    )
  end

  it 'looks up the confirmed name when rolling back before save' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'snapshot_id' => 24
    )
    allow(NodeCtld::Db).to receive(:new).and_return(instance_double(NodeCtld::Db))
    # rubocop:disable RSpec/ReceiveMessages
    allow(cmd).to receive(:get_confirmed_snapshot_name).and_return('snap-db')
    allow(cmd).to receive(:zfs).and_return(ret: :ok)
    # rubocop:enable RSpec/ReceiveMessages

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/ct/101@snap-db',
      valid_rcs: [1]
    )
  end
end
