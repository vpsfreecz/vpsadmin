# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/destroy_snapshot'

RSpec.describe NodeCtld::Commands::Dataset::DestroySnapshot do
  let(:driver) { build_storage_driver }
  let(:db) { instance_double(NodeCtld::Db, close: nil) }

  it 'destroys a confirmed snapshot on a root dataset' do
    allow(NodeCtld::Db).to receive(:new)

    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'snapshot' => { 'id' => 1, 'name' => 'snap-root', 'confirmed' => 'confirmed' }
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101@snap-root'
    )
    expect(NodeCtld::Db).not_to have_received(:new)
  end

  it 'looks up an unconfirmed snapshot on a root dataset in the database' do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(db).to receive(:prepared).with(
      'SELECT name FROM snapshots WHERE id = ?',
      42
    ).and_return(double(get!: { 'name' => 'snap-db' }))

    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'snapshot' => { 'id' => 42, 'name' => 'ignored', 'confirmed' => 'confirm_create' }
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101@snap-db'
    )
    expect(db).to have_received(:close)
  end

  it 'destroys a confirmed snapshot on a branch dataset' do
    allow(NodeCtld::Db).to receive(:new)

    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'branch' => 'branch-head.0',
      'snapshot' => { 'id' => 7, 'name' => 'snap-branch', 'confirmed' => 'confirmed' }
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101/tree.0/branch-head.0@snap-branch'
    )
    expect(NodeCtld::Db).not_to have_received(:new)
  end

  it 'looks up an unconfirmed branch snapshot in the database' do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(db).to receive(:prepared).with(
      'SELECT name FROM snapshots WHERE id = ?',
      99
    ).and_return(double(get!: { 'name' => 'snap-branch-db' }))

    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'branch' => 'branch-head.0',
      'snapshot' => { 'id' => 99, 'name' => 'ignored', 'confirmed' => 'confirm_create' }
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101/tree.0/branch-head.0@snap-branch-db'
    )
    expect(db).to have_received(:close)
  end
end
