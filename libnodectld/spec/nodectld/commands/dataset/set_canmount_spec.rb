# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/set_canmount'

RSpec.describe NodeCtld::Commands::Dataset::SetCanmount do
  let(:driver) { build_storage_driver }

  it 'sets canmount and mounts each dataset when requested' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'datasets' => %w[101 101/private],
      'canmount' => 'on',
      'mount' => true
    )
    allow(cmd).to receive(:zfs)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(:set, 'canmount=on', 'tank/ct/101')
    expect(cmd).to have_received(:zfs).with(:mount, nil, 'tank/ct/101')
    expect(cmd).to have_received(:zfs).with(:set, 'canmount=on', 'tank/ct/101/private')
    expect(cmd).to have_received(:zfs).with(:mount, nil, 'tank/ct/101/private')
  end

  it 'has a no-op rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'datasets' => ['101'],
      'canmount' => 'off',
      'mount' => false
    )

    expect(cmd.rollback).to eq(ret: :ok)
  end
end
