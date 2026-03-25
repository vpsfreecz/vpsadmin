# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset_tree/destroy'

RSpec.describe NodeCtld::Commands::DatasetTree::Destroy do
  let(:driver) { build_storage_driver }

  it 'destroys the tree dataset path' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0'
    )
    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101/tree.0'
    )
  end
end
