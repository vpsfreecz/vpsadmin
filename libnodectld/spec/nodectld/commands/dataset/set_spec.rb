# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/set'

RSpec.describe NodeCtld::Commands::Dataset::Set do
  let(:driver) { build_storage_driver }

  it 'sets the new property values on exec' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101',
      'properties' => {
        'compression' => [false, true],
        'quota' => [5, 10]
      }
    )
    allow(cmd).to receive(:zfs)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :set,
      'compression="on"',
      'tank/ct/101'
    )
    expect(cmd).to have_received(:zfs).with(
      :set,
      'quota="10M"',
      'tank/ct/101'
    )
  end

  it 'restores the old property values on rollback' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101',
      'properties' => {
        'compression' => [false, true],
        'quota' => [5, 10]
      }
    )
    allow(cmd).to receive(:zfs)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(
      :set,
      'compression="off"',
      'tank/ct/101'
    )
    expect(cmd).to have_received(:zfs).with(
      :set,
      'quota="5M"',
      'tank/ct/101'
    )
  end
end
