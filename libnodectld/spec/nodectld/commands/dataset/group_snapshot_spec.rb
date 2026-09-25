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
      strict_group_snapshot_receipt: nil,
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

  it 'ignores supplied names and uses its own timestamp' do
    fixed_time = Time.utc(2026, 6, 13, 12, 0, 0)
    named_cmd = described_class.new(
      driver,
      'snapshots' => snapshots,
      'name' => 'custom-name',
      'created_at' => '2026-06-13 12:00:00'
    )

    allow(Time).to receive(:now).and_return(fixed_time)
    allow(named_cmd).to receive(:zfs).with(
      :snapshot,
      nil,
      'tank/ct/101@2026-06-13T12:00:00 tank/ct/102@2026-06-13T12:00:00'
    ).and_return(ret: :ok)

    expect(named_cmd.exec).to eq(ret: :ok)
    expect(JSON.parse(File.read(named_cmd.send(:state_file_path)))).to eq(
      'name' => '2026-06-13T12:00:00',
      'created_at' => '2026-06-13 12:00:00'
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

  it 'uses the planned name and all-member receipt instead of a saved first-member state' do
    name = '2026-09-24T12:00:00'
    paths = snapshots.map { |row| "#{row.fetch('pool_fs')}/#{row.fetch('dataset_name')}@#{name}" }
    before = paths.map do |path|
      { presence: :missing, path:, owner_guid: '1001',
        graph_digest: NodeCtld::StorageGroupSnapshotReceipt::EMPTY_GRAPH_DIGEST,
        empty_dependencies: true }
    end
    after = before.map.with_index do |item, index|
      item.merge(presence: :present, guid: (9001 + index).to_s)
    end
    receipt = double(before:, observe_all!: after)
    strict_driver = instance_double(
      NodeCtld::Command, id: 123, progress: nil, 'progress=': nil,
                         log_type: :spec, strict_group_snapshot_receipt: receipt
    )
    strict_cmd = described_class.new(
      strict_driver, 'snapshots' => snapshots, 'planned_snapshot_name' => name
    )
    File.write(strict_cmd.send(:state_file_path), JSON.dump(name: 'wrong', created_at: 'wrong'))
    allow(strict_cmd).to receive(:zfs).with(
      :snapshot, nil, paths.join(' ')
    ).and_return(ret: :ok)

    expect(strict_cmd.exec).to eq(ret: :ok)
    expect(strict_cmd.storage_observation(:execute)).to eq([before, after])
    expect(strict_cmd.instance_variable_get(:@name)).to eq(name)
    expect(strict_cmd).to have_received(:zfs).with(:snapshot, nil, paths.join(' '))
  end

  it 'refuses strict rollback when a target GUID changed before any destroy' do
    name = '2026-09-24T12:00:00'
    paths = snapshots.map { |row| "#{row.fetch('pool_fs')}/#{row.fetch('dataset_name')}@#{name}" }
    before = paths.map.with_index do |path, index|
      { presence: :present, path:, guid: (9001 + index).to_s,
        owner_guid: '1001', empty_dependencies: true }
    end
    before.first[:guid] = '9999'
    targets = paths.map { |path| { path:, owner_guid: '1001' } }
    receipt = double(before:, targets:, created_guids: %w[9001 9002], observe_all!: before)
    allow(receipt).to receive(:observe_target!).and_return(before.first)
    strict_driver = instance_double(
      NodeCtld::Command, id: 123, progress: nil, 'progress=': nil,
                         log_type: :spec, strict_group_snapshot_receipt: receipt
    )
    strict_cmd = described_class.new(
      strict_driver, 'snapshots' => snapshots, 'planned_snapshot_name' => name
    )
    allow(strict_cmd).to receive(:zfs)

    expect { strict_cmd.rollback }.to raise_error(/identity changed/)
    expect(strict_cmd).not_to have_received(:zfs)
  end

  it 'rechecks strict rollback identity immediately before each destroy' do
    name = '2026-09-24T12:00:00'
    paths = snapshots.map { |row| "#{row.fetch('pool_fs')}/#{row.fetch('dataset_name')}@#{name}" }
    before = paths.map.with_index do |path, index|
      { presence: :present, path:, guid: (9001 + index).to_s,
        owner_guid: '1001', empty_dependencies: true }
    end
    targets = paths.map { |path| { path:, owner_guid: '1001' } }
    receipt = double(before:, targets:, created_guids: %w[9001 9002], observe_all!: before)
    allow(receipt).to receive(:observe_target!).and_return(before.first.merge(guid: '9999'))
    strict_driver = instance_double(
      NodeCtld::Command, id: 123, progress: nil, 'progress=': nil,
                         log_type: :spec, strict_group_snapshot_receipt: receipt
    )
    strict_cmd = described_class.new(
      strict_driver, 'snapshots' => snapshots, 'planned_snapshot_name' => name
    )
    allow(strict_cmd).to receive(:zfs)

    expect { strict_cmd.rollback }.to raise_error(/identity changed/)
    expect(strict_cmd).not_to have_received(:zfs)
  end
end
