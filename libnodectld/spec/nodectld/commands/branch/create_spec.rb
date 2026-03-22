# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/branch/create'

RSpec.describe NodeCtld::Commands::Branch::Create do
  let(:driver) { build_storage_driver }

  it 'clones and promotes a new branch from an existing branch snapshot' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'from_branch_name' => 'branch-head.0',
      'from_snapshot' => 'snap-0003',
      'new_branch_name' => 'branch-s3.1'
    )
    calls = []
    expected = [
      [
        :clone,
        '-o canmount=noauto -o readonly=on',
        'tank/backup/101/tree.0/branch-head.0@snap-0003 ' \
        'tank/backup/101/tree.0/branch-s3.1'
      ],
      [
        :promote,
        nil,
        'tank/backup/101/tree.0/branch-s3.1'
      ]
    ]

    allow(cmd).to receive(:zfs) { |*args| calls << args }

    cmd.exec

    expect(calls).to eq(expected)
  end

  it 'creates a read-only empty branch when there is no source branch' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'new_branch_name' => 'branch-empty.0'
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :create,
      '-o canmount=noauto -o readonly=on',
      'tank/backup/101/tree.0/branch-empty.0'
    )
  end

  it 'promotes the original branch back and destroys the cloned branch on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'from_branch_name' => 'branch-head.0',
      'new_branch_name' => 'branch-s3.1'
    )
    calls = []
    expected = [
      [
        :promote,
        nil,
        'tank/backup/101/tree.0/branch-head.0'
      ],
      [
        :destroy,
        nil,
        'tank/backup/101/tree.0/branch-s3.1'
      ]
    ]

    allow(cmd).to receive(:zfs) { |*args| calls << args }

    cmd.rollback

    expect(calls).to eq(expected)
  end

  it 'destroys only the new empty branch on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'new_branch_name' => 'branch-empty.0'
    )
    allow(cmd).to receive(:zfs)

    cmd.rollback

    expect(cmd).to have_received(:zfs).once.with(
      :destroy,
      nil,
      'tank/backup/101/tree.0/branch-empty.0'
    )
  end
end
