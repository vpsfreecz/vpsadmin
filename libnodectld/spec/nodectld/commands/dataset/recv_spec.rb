# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/recv'

RSpec.describe NodeCtld::Commands::Dataset::Recv do
  let(:driver) do
    instance_double(
      NodeCtld::Command,
      id: 123,
      progress: nil,
      'progress=': nil,
      log_type: :spec
    )
  end

  let(:db) { instance_double(NodeCtld::Db) }
  let(:socket) { instance_double(TCPSocket, close: nil) }

  before do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(TCPSocket).to receive(:new).and_return(socket)
  end

  def install_mbuffer_cfg(receive_command: 'mbuffer')
    $CFG = NodeCtldSpec::FakeCfg.new(
      mbuffer: {
        receive: {
          command: receive_command,
          block_size: '1M',
          buffer_size: '128M',
          start_writing_at: 60,
          timeout: 5
        }
      }
    )
  end

  def build_command(snapshots)
    described_class.new(
      driver,
      'addr' => '127.0.0.1',
      'port' => 39_001,
      'dst_pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'branch' => 'branch-2024-01-01.0',
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
    allow(cmd).to receive(:killall_subprocesses)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:killall_subprocesses)
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
    allow(cmd).to receive(:killall_subprocesses)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:killall_subprocesses)
    expect(cmd).to have_received(:zfs).once.with(
      :destroy, nil,
      'tank/backup/101/tree.0/branch-2024-01-01.0@snap-only',
      valid_rcs: [1]
    )
  end

  it 'uses the configured receive mbuffer command during exec' do
    install_mbuffer_cfg(receive_command: '/run/test/faulty-mbuffer')

    cmd = build_command(
      [
        { 'id' => 1, 'confirmed' => 'confirmed', 'name' => 'snap-only' }
      ]
    )

    allow(cmd).to receive(:log)
    allow(cmd).to receive(:blocking_fork)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:log).with(
      :work,
      cmd,
      include('/run/test/faulty-mbuffer -q -I 39001')
    )
    expect(cmd).to have_received(:blocking_fork)
  end
end
