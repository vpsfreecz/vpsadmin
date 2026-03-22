# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/local_rollback'

RSpec.describe NodeCtld::Commands::Dataset::LocalRollback do
  let(:driver) { build_storage_driver }

  def build_command(descendants = [])
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'snapshot' => 'snap-0007',
      'descendant_datasets' => descendants
    )
  end

  it 'ignores an unmount failure when the dataset is already not mounted' do
    cmd = build_command
    calls = []
    expected = [
      [:umount, nil, 'tank/ct/101'],
      [:rollback, '-r', 'tank/ct/101@snap-0007'],
      [:mount, nil, 'tank/ct/101']
    ]

    allow(cmd).to receive(:zfs) do |*args|
      calls << args

      next unless args == [:umount, nil, 'tank/ct/101']

      raise system_command_failed(
        output: 'cannot unmount tank/ct/101: not currently mounted'
      )
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(calls).to eq(expected)
  end

  it 're-raises unexpected unmount failures' do
    cmd = build_command

    allow(cmd).to receive(:zfs).with(:umount, nil, 'tank/ct/101').and_raise(
      system_command_failed(output: 'cannot unmount tank/ct/101: permission denied')
    )

    expect { cmd.exec }.to raise_error(NodeCtld::SystemCommandFailed)
  end

  it 'rolls the dataset back and remounts descendants' do
    calls = []
    expected = [
      [:umount, nil, 'tank/ct/101'],
      [:rollback, '-r', 'tank/ct/101@snap-0007'],
      [:mount, nil, 'tank/ct/101'],
      [:mount, nil, 'tank/ct/101/var'],
      [:mount, nil, 'tank/ct/101/var/lib/mysql']
    ]
    cmd = build_command(
      [
        { 'full_name' => '101/var' },
        { 'full_name' => '101/var/lib/mysql' }
      ]
    )

    allow(cmd).to receive(:zfs) { |*args| calls << args }

    expect(cmd.exec).to eq(ret: :ok)
    expect(calls).to eq(expected)
  end
end
