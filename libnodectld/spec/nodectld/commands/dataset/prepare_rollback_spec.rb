# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/prepare_rollback'

RSpec.describe NodeCtld::Commands::Dataset::PrepareRollback do
  let(:driver) { build_storage_driver }

  it 'creates the rollback dataset with canmount disabled' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101'
    )
    allow(cmd).to receive(:zfs)

    cmd.exec

    expect(cmd).to have_received(:zfs).with(
      :create,
      '-o canmount=noauto',
      'tank/ct/101.rollback'
    )
  end

  it 'destroys the rollback dataset on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101'
    )
    allow(cmd).to receive(:zfs)

    cmd.rollback

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/ct/101.rollback'
    )
  end
end
