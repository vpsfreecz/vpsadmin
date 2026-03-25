# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/inherit'
require 'nodectld/commands/dataset/set'

RSpec.describe NodeCtld::Commands::Dataset::Inherit do
  let(:driver) { build_storage_driver }

  it 'inherits each property on exec' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101',
      'properties' => { 'compression' => 'lz4', 'quota' => '10G' }
    )
    allow(cmd).to receive(:zfs)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:zfs).with(:inherit, 'compression', 'tank/ct/101')
    expect(cmd).to have_received(:zfs).with(:inherit, 'quota', 'tank/ct/101')
  end

  it 'rolls back by delegating to Dataset::Set' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'name' => '101',
      'properties' => { 'compression' => 'lz4' }
    )
    allow(cmd).to receive(:call_cmd).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:call_cmd).with(
      NodeCtld::Commands::Dataset::Set,
      hash_including(
        pool_fs: 'tank/ct',
        name: '101',
        properties: { 'compression' => [nil, 'lz4'] }
      )
    )
  end
end
