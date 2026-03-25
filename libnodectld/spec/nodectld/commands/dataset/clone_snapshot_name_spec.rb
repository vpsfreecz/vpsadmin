# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/clone_snapshot_name'

RSpec.describe NodeCtld::Commands::Dataset::CloneSnapshotName do
  let(:driver) { build_storage_driver }
  let(:db) { instance_double(NodeCtld::Db, close: nil) }

  it 'copies current names on exec and restores original names on rollback' do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(db).to receive(:query).and_return(
      [
        { 'id' => 10, 'name' => 'src-a' },
        { 'id' => 11, 'name' => 'src-b' }
      ]
    )
    allow(db).to receive(:prepared)

    cmd = described_class.new(
      driver,
      'snapshots' => {
        '10' => ['old-a', 20],
        '11' => ['old-b', 21]
      }
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ? WHERE id = ?',
      'src-a',
      20
    )
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ? WHERE id = ?',
      'src-b',
      21
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ? WHERE id = ?',
      'old-a',
      20
    )
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ? WHERE id = ?',
      'old-b',
      21
    )
    expect(db).to have_received(:close).at_least(:once)
  end
end
