# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset_tree/create'

RSpec.describe NodeCtld::Commands::DatasetTree::Create do
  let(:driver) { build_storage_driver }

  it 'creates the tree dataset with canmount disabled' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0'
    )
    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :create,
      '-o canmount=noauto',
      'tank/backup/101/tree.0'
    )
  end

  it 'destroys the tree dataset on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0'
    )
    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101/tree.0'
    )
  end
end
