# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/mounts'
require 'nodectld/vps_config'
require 'nodectld/vps_config/mount'
require 'nodectld/ct_hook_installer'

RSpec.describe NodeCtld::Commands::Vps::Mounts do
  let(:driver) { build_storage_driver }
  let(:mounts) { [{ 'id' => 10, 'dst' => '/mnt/data', 'mount_type' => 'bind' }] }
  let(:cfg) do
    instance_spy(NodeCtld::VpsConfig::TopLevel, mounts: mounts)
  end
  let(:installer) do
    instance_spy(NodeCtld::CtHookInstaller)
  end
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'mounts' => mounts
    )
  end

  before do
    allow(NodeCtld::VpsConfig).to receive(:open).and_return(cfg)
    allow(NodeCtld::VpsConfig::Mount).to receive(:load) { |raw| raw }
    allow(NodeCtld::CtHookInstaller).to receive(:new).and_return(installer)
    allow(cfg).to receive(:mounts=)
  end

  it 'backs up the config, writes mounts, and saves it' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cfg).to have_received(:backup)
    expect(cfg).to have_received(:mounts=).with(mounts)
    expect(cfg).to have_received(:save)
  end

  it 'installs hooks when mounts are present' do
    cmd.exec

    expect(installer).to have_received(:install_hooks).with(%w[pre-start post-mount])
    expect(installer).not_to have_received(:uninstall_hooks)
  end

  it 'uninstalls hooks when the mount list is empty' do
    empty_cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'mounts' => []
    )
    allow(cfg).to receive(:mounts).and_return([])

    empty_cmd.exec

    expect(installer).to have_received(:uninstall_hooks).with(%w[pre-start post-mount])
    expect(installer).not_to have_received(:install_hooks)
  end

  it 'restores the config and reinstalls hooks when restored mounts are present' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(cfg).to have_received(:restore)
    expect(installer).to have_received(:install_hooks).with(%w[pre-start post-mount])
  end

  it 'restores the config and uninstalls hooks when restored mounts are empty' do
    allow(cfg).to receive(:mounts).and_return([])

    expect(cmd.rollback).to eq(ret: :ok)
    expect(installer).to have_received(:uninstall_hooks).with(%w[pre-start post-mount])
  end
end
