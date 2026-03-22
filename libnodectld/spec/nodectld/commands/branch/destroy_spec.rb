# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/branch/destroy'

RSpec.describe NodeCtld::Commands::Branch::Destroy do
  let(:driver) { build_storage_driver }

  it 'destroys the branch dataset path' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'branch' => 'branch-head.0'
    )

    allow(cmd).to receive(:zfs).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/backup/101/tree.0/branch-head.0'
    )
  end
end
