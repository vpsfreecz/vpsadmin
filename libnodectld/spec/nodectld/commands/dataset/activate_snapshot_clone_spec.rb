# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/activate_snapshot_clone'

RSpec.describe NodeCtld::Commands::Dataset::ActivateSnapshotClone do
  let(:driver) { build_storage_driver }

  it 'sets canmount=on, mounts the clone, and inherits sharenfs' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'clone_name' => '42.snapshot'
    )
    calls = []

    allow(cmd).to receive(:zfs) do |*args, **kwargs|
      calls << [args, kwargs]
      { ret: :ok }
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(calls).to eq([
                          [[:set, 'canmount=on', 'tank/backup/vpsadmin/mount/42.snapshot'], {}],
                          [[:mount, nil, 'tank/backup/vpsadmin/mount/42.snapshot'], { valid_rcs: [1] }],
                          [[:inherit, 'sharenfs', 'tank/backup/vpsadmin/mount/42.snapshot'], {}]
                        ])
  end

  it 'sets sharenfs=off on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'clone_name' => '42.snapshot'
    )

    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :set,
      'sharenfs=off',
      'tank/backup/vpsadmin/mount/42.snapshot'
    )
  end
end
