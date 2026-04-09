# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/export/del_hosts'
require 'nodectld/nfs_server'

RSpec.describe NodeCtld::Commands::Export::DelHosts do
  let(:driver) { build_storage_driver }
  let(:server) { instance_spy(NodeCtld::NfsServer) }
  let(:hosts) do
    [
      {
        'address' => '192.0.2.50',
        'options' => {
          'fsid' => 42,
          'rw' => true,
          'sync' => true,
          'subtree_check' => false,
          'root_squash' => false
        }
      }
    ]
  end

  before do
    allow(NodeCtld::NfsServer).to receive(:new).with(42, nil).and_return(server)
    allow(server).to receive(:add_filesystem_export)
    allow(server).to receive(:add_snapshot_export)
    allow(server).to receive(:remove_export)
  end

  it 'removes exports on exec and recreates filesystem hosts on rollback' do
    cmd = described_class.new(
      driver,
      'export_id' => 42,
      'pool_fs' => 'tank/ct',
      'dataset_name' => 'user.dataset',
      'snapshot_clone' => nil,
      'as' => '/exports/user.dataset',
      'hosts' => hosts
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(server).to have_received(:remove_export).with('/exports/user.dataset', '192.0.2.50')

    expect(cmd.rollback).to eq(ret: :ok)
    expect(server).to have_received(:add_filesystem_export).with(
      'tank/ct',
      'user.dataset',
      '/exports/user.dataset',
      '192.0.2.50',
      hosts.first.fetch('options')
    )
  end

  it 'recreates snapshot-clone hosts on rollback' do
    cmd = described_class.new(
      driver,
      'export_id' => 42,
      'pool_fs' => 'tank/ct',
      'dataset_name' => 'user.dataset',
      'snapshot_clone' => 'snap-clone',
      'as' => '/exports/user.dataset',
      'hosts' => hosts
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd.rollback).to eq(ret: :ok)

    expect(server).to have_received(:add_snapshot_export).with(
      'tank/ct',
      'snap-clone',
      '/exports/user.dataset',
      '192.0.2.50',
      hosts.first.fetch('options')
    )
  end
end
