# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/local_send'

RSpec.describe NodeCtld::Commands::Dataset::LocalSend do
  let(:driver) do
    instance_double(NodeCtld::Command, progress: nil, 'progress=': nil, log_type: :spec)
  end

  let(:db) { instance_double(NodeCtld::Db) }

  before do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
  end

  def build_command(snapshots)
    described_class.new(
      driver,
      'dst_pool_fs' => 'tank/backup',
      'dst_dataset_name' => '101',
      'dst_tree' => 'tree.0',
      'dst_branch' => 'branch-2024-01-01.0',
      'snapshots' => snapshots
    )
  end

  it 'preserves the common base snapshot on incremental rollback' do
    allow(db).to receive(:prepared).and_return(
      double(get!: { 'name' => 'snap-base' }),
      double(get!: { 'name' => 'snap-new-1' }),
      double(get!: { 'name' => 'snap-new-2' })
    )

    cmd = build_command(
      [
        { 'id' => 1, 'confirmed' => 'confirmed', 'name' => 'snap-base' },
        { 'id' => 2, 'confirmed' => 'confirmed', 'name' => 'snap-new-1' },
        { 'id' => 3, 'confirmed' => 'confirmed', 'name' => 'snap-new-2' }
      ]
    )

    allow(cmd).to receive(:zfs)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-new-2',
      valid_rcs: [1]
    )
    expect(cmd).to have_received(:zfs).with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-new-1',
      valid_rcs: [1]
    )
    expect(cmd).not_to have_received(:zfs).with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-base',
      anything
    )
  end

  it 'destroys the single received snapshot on rollback' do
    cmd = build_command(
      [
        { 'id' => 1, 'confirmed' => 'confirmed', 'name' => 'snap-only' }
      ]
    )

    allow(cmd).to receive(:zfs)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).once.with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-only',
      valid_rcs: [1]
    )
  end

  it 'resolves snapshot names from the database when the rollback input is not confirmed yet' do
    allow(db).to receive(:prepared).with(
      'SELECT name FROM snapshots WHERE id = ?',
      42
    ).and_return(double(get!: { 'name' => 'snap-db' }))

    cmd = build_command(
      [
        { 'id' => 42, 'confirmed' => 'confirm_create', 'name' => 'ignored-name' }
      ]
    )

    allow(cmd).to receive(:zfs)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-db',
      valid_rcs: [1]
    )
  end
end
