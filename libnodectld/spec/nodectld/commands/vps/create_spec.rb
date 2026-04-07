# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/create'
require 'nodectld/commands/vps/destroy'
require 'nodectld/ct_hook_installer'

RSpec.describe NodeCtld::Commands::Vps::Create do
  let(:driver) { build_vps_driver }
  let(:hook_installer) { instance_spy(NodeCtld::CtHookInstaller) }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'pool_name' => 'tank',
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'userns_map' => '0:100000:65536',
      'map_mode' => 'native',
      'hostname' => 'spec-vps',
      'distribution' => 'specos',
      'version' => '1',
      'arch' => 'x86_64',
      'vendor' => 'spec',
      'variant' => 'base',
      'empty' => false
    )
  end

  before do
    allow(NodeCtld::CtHookInstaller).to receive(:new).with('tank/ct', 101).and_return(hook_installer)
  end

  it 'creates the container, clears image mounts, applies limits, and installs hooks' do
    calls = []

    allow(cmd).to receive(:osctl_pool) do |*args|
      calls << args
      { ret: :ok }
    end

    expect(cmd.exec).to eq(ret: :ok)

    create_pool, create_cmd, create_vps_id, create_opts = calls[0]
    expect([create_pool, create_cmd, create_vps_id]).to eq(['tank', %i[ct create], 101])
    expect(create_opts).to include(
      user: '0:100000:65536',
      dataset: 'tank/ct/101',
      map_mode: 'native',
      distribution: 'specos',
      version: '1',
      arch: 'x86_64',
      vendor: 'spec',
      variant: 'base'
    )
    expect(calls[1..]).to eq(
      [
        ['tank', %i[ct mounts clear], 101],
        ['tank', %i[ct set hostname], [101, 'spec-vps']],
        ['tank', %i[ct prlimits set], [101, 'nofile', 1024, 1_048_576]],
        ['tank', %i[ct prlimits set], [101, 'nproc', 131_072, 1_048_576]],
        ['tank', %i[ct prlimits set], [101, 'memlock', 65_536, 'unlimited']]
      ]
    )
    expect(hook_installer).to have_received(:install_hooks).with(%w[veth-up])
  end

  it 'can skip the image and rolls back through Vps::Destroy' do
    empty_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'pool_name' => 'tank',
      'pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'userns_map' => '0:100000:65536',
      'map_mode' => 'native',
      'hostname' => nil,
      'distribution' => 'specos',
      'version' => '1',
      'arch' => 'x86_64',
      'vendor' => 'spec',
      'variant' => 'base',
      'empty' => true
    )

    allow(NodeCtld::CtHookInstaller).to receive(:new).with('tank/ct', 101).and_return(hook_installer)
    allow(empty_cmd).to receive_messages(osctl_pool: { ret: :ok }, call_cmd: { ret: :ok })

    expect(empty_cmd.exec).to eq(ret: :ok)
    expect(empty_cmd.rollback).to eq(ret: :ok)
    expect(empty_cmd).to have_received(:osctl_pool).with(
      'tank',
      %i[ct create],
      101,
      hash_including(skip_image: true)
    )
    expect(empty_cmd).to have_received(:call_cmd).with(
      NodeCtld::Commands::Vps::Destroy,
      vps_id: 101
    )
  end
end
