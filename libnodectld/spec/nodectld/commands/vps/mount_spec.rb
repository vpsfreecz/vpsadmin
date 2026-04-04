# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/mount'
require 'nodectld/commands/vps/umount'
require 'nodectld/mounter'

RSpec.describe NodeCtld::Commands::Vps::Mount do
  let(:driver) { build_storage_driver }
  let(:mounts) do
    [
      { 'id' => 10, 'dst' => '/mnt/first' },
      { 'id' => 11, 'dst' => '/mnt/second' }
    ]
  end
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'mounts' => mounts
    )
  end

  it 'is a no-op when the VPS is not running' do
    allow(cmd).to receive(:status).and_return(:stopped)
    allow(NodeCtld::Mounter).to receive(:new)

    expect(cmd.exec).to eq(ret: :ok)
    expect(NodeCtld::Mounter).not_to have_received(:new)
  end

  it 'mounts all supplied mounts when the VPS is running' do
    mounter = instance_spy(NodeCtld::Mounter)

    allow(cmd).to receive(:status).and_return(:running)
    allow(NodeCtld::Mounter).to receive(:new).with('tank/ct', 101).and_return(mounter)

    expect(cmd.exec).to eq(ret: :ok)
    expect(mounter).to have_received(:mount_after_start).with(mounts[0], true).ordered
    expect(mounter).to have_received(:mount_after_start).with(mounts[1], true).ordered
  end

  it 'rolls back by delegating to Vps::Umount with reversed mounts' do
    allow(cmd).to receive(:call_cmd).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:call_cmd).with(
      NodeCtld::Commands::Vps::Umount,
      pool_fs: 'tank/ct',
      vps_id: 101,
      mounts: mounts.reverse
    )
  end
end
