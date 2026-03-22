# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/clone_snapshot'

RSpec.describe NodeCtld::Commands::Dataset::CloneSnapshot do
  let(:driver) { build_storage_driver }

  it 'clones a root snapshot into the mounted clone path' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'snapshot' => 'snap-1',
      'clone_name' => '42.snapshot'
    )

    allow(cmd).to receive(:zfs)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :clone,
      '-o readonly=on',
      'tank/backup/101@snap-1 tank/backup/vpsadmin/mount/42.snapshot'
    )
  end

  it 'clones a branch snapshot into the mounted clone path' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'dataset_tree' => 'tree.0',
      'branch' => 'branch-head.0',
      'snapshot' => 'snap-2',
      'clone_name' => '43.snapshot'
    )

    allow(cmd).to receive(:zfs)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :clone,
      '-o readonly=on',
      'tank/backup/101/tree.0/branch-head.0@snap-2 ' \
      'tank/backup/vpsadmin/mount/43.snapshot'
    )
  end

  it 'applies uidmap/gidmap to the clone when they are present' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'snapshot' => 'snap-3',
      'clone_name' => '44.snapshot',
      'uidmap' => ['0:100000:65536'],
      'gidmap' => ['0:100000:65536']
    )

    calls = []
    allow(cmd).to receive(:zfs) { |*args| calls << args }

    expect(cmd.exec).to eq(ret: :ok)
    expect(calls).to eq([
                          [
                            :clone,
                            '-o readonly=on',
                            'tank/backup/101@snap-3 tank/backup/vpsadmin/mount/44.snapshot'
                          ],
                          [:umount, nil, 'tank/backup/vpsadmin/mount/44.snapshot'],
                          [
                            :set,
                            'uidmap="0:100000:65536" gidmap="0:100000:65536"',
                            'tank/backup/vpsadmin/mount/44.snapshot'
                          ],
                          [:mount, nil, 'tank/backup/vpsadmin/mount/44.snapshot']
                        ])
  end

  it 'destroys the clone on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'snapshot' => 'snap-4',
      'clone_name' => '45.snapshot'
    )

    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/vpsadmin/mount/45.snapshot',
      valid_rcs: [1]
    )
  end
end
