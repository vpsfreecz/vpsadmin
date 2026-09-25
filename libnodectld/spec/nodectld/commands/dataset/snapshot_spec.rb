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

  def guarded_command(guid: nil, list_failure: false)
    driver = build_storage_driver
    target = instance_double(NodeCtld::StorageMutationReceipt,
                             expected_path: 'tank/ct/101@2026-09-24T12:00:00',
                             expected_owner_guid: nil)
    allow(driver).to receive_messages(successful_snapshot_execute_identity: nil,
                                      storage_snapshot_target: target)
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct', 'dataset_name' => '101', 'snapshot_id' => 42,
      'planned_snapshot_name' => '2026-09-24T12:00:00',
      'storage_guard' => { 'token' => 'signed-token' }
    )
    snapshot_guid = guid
    allow(cmd).to receive(:zfs) do |action, options, path, **_kwargs|
      if action == :destroy
        snapshot_guid = nil
        next instance_double(OsCtl::Lib::SystemCommandResult)
      end

      raise 'unexpected ZFS call' unless action == :list &&
                                         options == '-H -t all -r -o name,guid' &&
                                         path == 'tank/ct/101'
      raise 'injected list failure' if list_failure

      output = "tank/ct/101\t1001\n"
      output += "tank/ct/101@2026-09-24T12:00:00\t#{snapshot_guid}\n" if snapshot_guid
      instance_double(OsCtl::Lib::SystemCommandResult,
                      exitstatus: 0, output:)
    end
    [cmd, ->(value) { snapshot_guid = value }]
  end

  it 'compensates a proven creation after a post-ZFS failure' do
    cmd, set_guid = guarded_command
    dataset = instance_double(NodeCtld::Dataset)
    allow(NodeCtld::Dataset).to receive(:new).and_return(dataset)
    allow(dataset).to receive(:snapshot) do |_pool, _name, **_opts|
      set_guid.call('9001')
      raise 'injected post-ZFS failure'
    end

    expect { cmd.exec }.to raise_error('injected post-ZFS failure')
    expect(cmd.rollback).to eq(ret: :ok)
    before, after = cmd.storage_observation(:execute)
    expect(before[:presence]).to eq(:missing)
    expect(after[:guid]).to eq('9001')
    expect(cmd.storage_observation(:rollback).last[:presence]).to eq(:missing)
  end

  it 'leaves an unchanged preexisting snapshot intact after rejected create' do
    cmd, = guarded_command(guid: '9002')
    allow(NodeCtld::Dataset).to receive(:new)

    expect { cmd.exec }.to raise_error('snapshot preflight is not proven missing; reconcile before retry')
    expect(cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::Dataset).not_to have_received(:new)
    expect(cmd.storage_observation(:rollback).last[:guid]).to eq('9002')
  end

  it 'does not treat a failed ZFS inventory as proof of absence or destroy a snapshot' do
    cmd, = guarded_command(list_failure: true)
    allow(NodeCtld::Dataset).to receive(:new)

    expect { cmd.exec }.to raise_error('snapshot preflight is not proven missing; reconcile before retry')
    expect { cmd.rollback }.to raise_error('snapshot identity is not bound to this attempt')
    expect(NodeCtld::Dataset).not_to have_received(:new)
    expect(cmd).not_to have_received(:zfs).with(:destroy, anything, anything)
    expect(cmd.storage_observation(:execute).first[:presence]).to eq(:unknown)
  end

  it 'refuses compensation when the owner filesystem identity changes' do
    cmd, set_guid = guarded_command
    dataset = instance_double(NodeCtld::Dataset)
    allow(NodeCtld::Dataset).to receive(:new).and_return(dataset)
    allow(dataset).to receive(:snapshot) do |_pool, _name, **_opts|
      set_guid.call('9001')
      raise 'injected post-ZFS failure'
    end
    expect { cmd.exec }.to raise_error('injected post-ZFS failure')

    allow(cmd).to receive(:zfs) do |action, _options, _path, **_kwargs|
      raise 'destroy must not run' if action == :destroy

      instance_double(OsCtl::Lib::SystemCommandResult,
                      exitstatus: 0,
                      output: "tank/ct/101\t2002\ntank/ct/101@2026-09-24T12:00:00\t9001\n")
    end
    expect { cmd.rollback }.to raise_error('snapshot identity is not bound to this attempt')
  end

  it 'keeps extra guarded input compatible with an older handler using Base' do
    legacy = Class.new(NodeCtld::Commands::Base) do
      def exec
        { ret: :ok, pool_fs: @pool_fs }
      end
    end

    cmd = legacy.new(build_storage_driver,
                     'pool_fs' => 'tank/ct', 'storage_guard' => { 'token' => 'new' })
    expect(cmd.exec).to eq(ret: :ok, pool_fs: 'tank/ct')
  end
end
