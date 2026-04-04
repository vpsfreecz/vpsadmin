# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/umount'
require 'nodectld/commands/vps/mount'
require 'nodectld/mounter'

RSpec.describe NodeCtld::Commands::Vps::Umount do
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

  it 'unmounts configured mounts and tracks the successfully unmounted subset' do
    mounter = instance_spy(NodeCtld::Mounter)

    allow(cmd).to receive(:status).and_return(:running)
    allow(NodeCtld::Mounter).to receive(:new).with('tank/ct', 101).and_return(mounter)
    allow(mounter).to receive(:umount).with(mounts[0])
    allow(mounter).to receive(:umount).with(mounts[1]).and_raise('boom')

    expect { cmd.exec }.to raise_error(RuntimeError, 'boom')
    expect(mounter).to have_received(:umount).with(mounts[0]).ordered
    expect(mounter).to have_received(:umount).with(mounts[1]).ordered
    expect(cmd.instance_variable_get(:@umounted_mounts)).to eq([mounts[0]])
  end

  it 'rolls back only the successfully unmounted subset in reverse order' do
    cmd.instance_variable_set(:@umounted_mounts, [mounts[0]])
    allow(cmd).to receive(:call_cmd).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:call_cmd).with(
      NodeCtld::Commands::Vps::Mount,
      pool_fs: 'tank/ct',
      vps_id: 101,
      mounts: [mounts[0]]
    )
  end

  it 'falls back to all mounts when rollback has no tracked subset' do
    allow(cmd).to receive(:call_cmd).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:call_cmd).with(
      NodeCtld::Commands::Vps::Mount,
      pool_fs: 'tank/ct',
      vps_id: 101,
      mounts: mounts.reverse
    )
  end
end
