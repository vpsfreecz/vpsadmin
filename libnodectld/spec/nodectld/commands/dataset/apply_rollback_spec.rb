# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/apply_rollback'

RSpec.describe NodeCtld::Commands::Dataset::ApplyRollback do
  let(:driver) { build_storage_driver }

  def build_command(descendants)
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'descendant_datasets' => descendants
    )
  end

  it 'ignores an unmount failure when the dataset is already not mounted' do
    origin_state = NodeCtldSpec::StorageCommandHelpers::FakeDatasetState.new('origin')
    cmd = build_command([])
    calls = []
    expected = [
      [[:umount, nil, 'tank/ct/101'], {}],
      [[:rename, nil, 'tank/ct/101.rollback tank/ct/101'], {}],
      [[:mount, nil, 'tank/ct/101'], {}],
      [[:share, '-a', ''], { valid_rcs: [1] }]
    ]

    allow(cmd).to receive(:dataset_properties).with(
      'tank/ct/101',
      %i[atime compression mountpoint quota recordsize refquota sync canmount uidmap gidmap]
    ).and_return(origin_state)
    allow(cmd).to receive(:osctl)
    allow(cmd).to receive(:zfs) do |*args, **kwargs|
      calls << [args, kwargs]

      next unless args == [:umount, nil, 'tank/ct/101']

      raise system_command_failed(
        output: 'cannot unmount tank/ct/101: not currently mounted'
      )
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(origin_state.applied_to).to eq(['tank/ct/101'])
    expect(calls).to eq(expected)
  end

  it 're-raises unexpected unmount failures' do
    cmd = build_command([])

    allow(cmd).to receive(:zfs).with(:umount, nil, 'tank/ct/101').and_raise(
      system_command_failed(output: 'permission denied')
    )

    expect { cmd.exec }.to raise_error(NodeCtld::SystemCommandFailed)
  end

  it 'moves children aside, restores the rollback dataset, and remounts descendants' do
    origin_state = NodeCtldSpec::StorageCommandHelpers::FakeDatasetState.new('origin')
    child_state = NodeCtldSpec::StorageCommandHelpers::FakeDatasetState.new('child')
    grandchild_state = NodeCtldSpec::StorageCommandHelpers::FakeDatasetState.new('grandchild')
    zfs_calls = []
    osctl_calls = []
    expected_zfs = [
      [[:umount, nil, 'tank/ct/101'], {}],
      [[:set, 'canmount=off', 'tank/ct/101/var/lib/mysql'], {}],
      [[:set, 'canmount=off', 'tank/ct/101/var'], {}],
      [[:rename, nil, 'tank/ct/101/var tank/ct/101.rollback/var'], {}],
      [[:rename, nil, 'tank/ct/101.rollback tank/ct/101'], {}],
      [[:mount, nil, 'tank/ct/101'], {}],
      [[:mount, nil, 'tank/ct/101/var'], {}],
      [[:mount, nil, 'tank/ct/101/var/lib/mysql'], {}],
      [[:share, '-a', ''], { valid_rcs: [1] }]
    ]
    expected_osctl = [
      [%i[trash-bin dataset add], 'tank/ct/101']
    ]

    cmd = build_command(
      [
        { 'name' => 'var', 'full_name' => '101/var' },
        { 'name' => 'mysql', 'full_name' => '101/var/lib/mysql' }
      ]
    )

    allow(cmd).to receive(:puts)
    allow(cmd).to receive(:osctl) { |*args| osctl_calls << args }
    allow(cmd).to receive(:dataset_properties)
      .with('tank/ct/101/var', [:canmount])
      .and_return(child_state)
    allow(cmd).to receive(:dataset_properties)
      .with('tank/ct/101/var/lib/mysql', [:canmount])
      .and_return(grandchild_state)
    allow(cmd).to receive(:dataset_properties).with(
      'tank/ct/101',
      %i[atime compression mountpoint quota recordsize refquota sync canmount uidmap gidmap]
    ).and_return(origin_state)
    allow(cmd).to receive(:zfs) do |*args, **kwargs|
      zfs_calls << [args, kwargs]
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(origin_state.applied_to).to eq(['tank/ct/101'])
    expect(child_state.applied_to).to eq(['tank/ct/101/var'])
    expect(grandchild_state.applied_to).to eq(['tank/ct/101/var/lib/mysql'])
    expect(zfs_calls).to eq(expected_zfs)
    expect(osctl_calls).to eq(expected_osctl)
  end
end
