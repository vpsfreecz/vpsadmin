# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/create'

RSpec.describe NodeCtld::Commands::Dataset::Create do
  let(:driver) { build_storage_driver }

  it 'creates the dataset and private directory when requested' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101',
      'options' => { 'compression' => 'lz4', 'quota' => 10 },
      'create_private' => true
    )
    allow(cmd).to receive(:zfs).and_return(double(output: "/tank/ct/101\n"))
    allow(cmd).to receive(:syscmd)
    allow($CFG).to receive(:get).with(:bin, :mkdir).and_return('/bin/mkdir')

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :create,
      '-p -o compression="lz4" -o quota="10M"',
      'tank/ct/101'
    )
    expect(cmd).to have_received(:zfs).with(
      :mount,
      nil,
      'tank/ct/101',
      valid_rcs: [1]
    )
    expect(cmd).to have_received(:zfs).with(
      :get,
      '-ovalue -H mountpoint',
      'tank/ct/101'
    )
    expect(cmd).to have_received(:syscmd).with(%r{/tank/ct/101/private})
  end

  it 'destroys the dataset on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101'
    )
    allow(cmd).to receive(:zfs)

    cmd.rollback

    expect(cmd).to have_received(:zfs).with(
      :destroy,
      nil,
      'tank/ct/101',
      valid_rcs: [1]
    )
  end
end
