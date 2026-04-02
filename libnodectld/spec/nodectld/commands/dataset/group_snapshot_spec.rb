# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'nodectld/remote_control'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/group_snapshot'

RSpec.describe NodeCtld::Commands::Dataset::GroupSnapshot do
  let(:driver) do
    instance_double(
      NodeCtld::Command,
      id: 123,
      progress: nil,
      'progress=': nil,
      log_type: :spec
    )
  end
  let(:tmpdir) { Dir.mktmpdir('group-snapshot-spec') }
  let(:snapshots) do
    [
      { 'pool_fs' => 'tank/ct', 'dataset_name' => '101', 'snapshot_id' => 11 },
      { 'pool_fs' => 'tank/ct', 'dataset_name' => '102', 'snapshot_id' => 12 }
    ]
  end
  let(:cmd) { described_class.new(driver, 'snapshots' => snapshots) }

  before do
    stub_const('NodeCtld::RemoteControl::RUNDIR', tmpdir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  it 'creates snapshots and stores crash-recovery state' do
    fixed_time = Time.utc(2024, 1, 2, 3, 4, 5)

    allow(Time).to receive(:now).and_return(fixed_time)
    allow(cmd).to receive(:zfs).with(
      :snapshot,
      nil,
      'tank/ct/101@2024-01-02T03:04:05 tank/ct/102@2024-01-02T03:04:05'
    ).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :snapshot,
      nil,
      'tank/ct/101@2024-01-02T03:04:05 tank/ct/102@2024-01-02T03:04:05'
    )

    expect(JSON.parse(File.read(cmd.send(:state_file_path)))).to eq(
      'name' => '2024-01-02T03:04:05',
      'created_at' => '2024-01-02 03:04:05'
    )
  end

  it 'reuses saved state when the snapshot already exists' do
    File.write(
      cmd.send(:state_file_path),
      JSON.dump(name: '2024-01-02T03:04:05', created_at: '2024-01-02 03:04:05')
    )
    allow(cmd).to receive(:log)
    allow(cmd).to receive(:zfs).with(
      :list,
      '-H -o name',
      'tank/ct/101@2024-01-02T03:04:05'
    ).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :list,
      '-H -o name',
      'tank/ct/101@2024-01-02T03:04:05'
    )
    expect(cmd).not_to have_received(:zfs).with(:snapshot, anything, anything)
  end

  it 'disregards stale saved state when the snapshot no longer exists' do
    File.write(
      cmd.send(:state_file_path),
      JSON.dump(name: '2024-01-02T03:04:05', created_at: '2024-01-02 03:04:05')
    )
    allow(cmd).to receive(:log)
    allow(cmd).to receive(:zfs).with(
      :list,
      '-H -o name',
      'tank/ct/101@2024-01-02T03:04:05'
    ).and_raise(system_command_failed)
    allow(cmd).to receive(:zfs).with(
      :snapshot,
      nil,
      include('tank/ct/101@', 'tank/ct/102@')
    ).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :snapshot,
      nil,
      include('tank/ct/101@', 'tank/ct/102@')
    )
    expect(JSON.parse(File.read(cmd.send(:state_file_path))).fetch('name')).not_to eq('2024-01-02T03:04:05')
  end

  it 'updates snapshot name and timestamp on save and removes the state file afterwards' do
    db = instance_spy(NodeCtld::Db)

    cmd.instance_variable_set(:@name, '2024-01-02T03:04:05')
    cmd.instance_variable_set(:@created_at, '2024-01-02 03:04:05')
    File.write(cmd.send(:state_file_path), JSON.dump(name: cmd.instance_variable_get(:@name)))

    allow(db).to receive(:prepared).with(
      'UPDATE snapshots SET name = ?, created_at = ? WHERE id IN (?,?)',
      '2024-01-02T03:04:05',
      '2024-01-02 03:04:05',
      11,
      12
    )

    cmd.on_save(db)
    cmd.post_save

    expect(db).to have_received(:prepared).with(
      'UPDATE snapshots SET name = ?, created_at = ? WHERE id IN (?,?)',
      '2024-01-02T03:04:05',
      '2024-01-02 03:04:05',
      11,
      12
    )

    expect(File.exist?(cmd.send(:state_file_path))).to be(false)
  end

  it 'destroys all created snapshots on rollback' do
    cmd.instance_variable_set(:@name, '2024-01-02T03:04:05')

    allow(cmd).to receive(:zfs).with(
      :destroy,
      nil,
      'tank/ct/101@2024-01-02T03:04:05',
      valid_rcs: [1]
    ).and_return(ret: :ok)
    allow(cmd).to receive(:zfs).with(
      :destroy,
      nil,
      'tank/ct/102@2024-01-02T03:04:05',
      valid_rcs: [1]
    ).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/ct/101@2024-01-02T03:04:05',
      valid_rcs: [1]
    )
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/ct/102@2024-01-02T03:04:05',
      valid_rcs: [1]
    )
  end
end
