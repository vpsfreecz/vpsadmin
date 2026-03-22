# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/deactivate_snapshot_clone'

RSpec.describe NodeCtld::Commands::Dataset::DeactivateSnapshotClone do
  let(:driver) { build_storage_driver }

  it 'sets sharenfs=off' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'clone_name' => '42.snapshot'
    )

    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :set,
      'sharenfs=off',
      'tank/backup/vpsadmin/mount/42.snapshot'
    )
  end

  it 'inherits sharenfs on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'clone_name' => '42.snapshot'
    )

    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :inherit,
      'sharenfs',
      'tank/backup/vpsadmin/mount/42.snapshot'
    )
  end
end
