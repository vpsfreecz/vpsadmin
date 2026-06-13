# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/rename'

RSpec.describe NodeCtld::Commands::Dataset::Rename do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'old_name' => '101',
      'new_name' => '202'
    )
  end

  it 'renames the dataset and creates missing parents' do
    allow(cmd).to receive(:zfs).with(
      :rename,
      '-p',
      'tank/backup/101 tank/backup/202'
    ).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :rename,
      '-p',
      'tank/backup/101 tank/backup/202'
    )
  end

  it 'renames the dataset back on rollback when possible' do
    allow(cmd).to receive(:zfs).with(
      :rename,
      '-p',
      'tank/backup/202 tank/backup/101',
      valid_rcs: [1]
    ).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :rename,
      '-p',
      'tank/backup/202 tank/backup/101',
      valid_rcs: [1]
    )
  end
end
