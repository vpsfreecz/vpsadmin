# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/boot'

RSpec.describe NodeCtld::Commands::Vps::Boot do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'distribution' => 'specos',
      'version' => '1',
      'arch' => 'x86_64',
      'vendor' => 'spec',
      'variant' => 'base',
      'mount_root_dataset' => '/rootfs',
      'start_timeout' => 45
    )
  end

  it 'boots the VPS into rescue mode with the requested template and mount path' do
    allow(cmd).to receive_messages(osctl: { ret: :ok }, osctl_parse: { boot_rootfs: '/tmp/spec-rootfs' }, fork_chroot_wait: 0)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct boot],
      101,
      hash_including(
        force: true,
        distribution: 'specos',
        version: '1',
        arch: 'x86_64',
        vendor: 'spec',
        variant: 'base',
        zfs_property: 'refquota=10G',
        wait: 45,
        mount_root_dataset: '/rootfs'
      )
    )
    expect(cmd).to have_received(:fork_chroot_wait)
  end

  it 'has a no-op rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
