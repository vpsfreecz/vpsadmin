# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/user_namespace/disuse'

RSpec.describe NodeCtld::Commands::UserNamespace::Disuse do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => 'tank/ct',
      'vps_id' => 101,
      'name' => '42',
      'uidmap' => ['0:100000:65536'],
      'gidmap' => ['0:100000:65536']
    )
  end

  before do
    stub_const('NodeCtld::OsCtlUsers', Class.new)
    allow(NodeCtld::OsCtlUsers).to receive_messages(
      add_vps: { ret: :ok },
      remove_vps: { ret: :ok }
    )
  end

  it 'removes the osctl user on exec and adds it back on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(NodeCtld::OsCtlUsers).to have_received(:remove_vps).with(
      pool_fs: 'tank/ct',
      vps_id: 101,
      user_name: '42'
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::OsCtlUsers).to have_received(:add_vps).with(
      pool_fs: 'tank/ct',
      vps_id: 101,
      user_name: '42',
      uidmap: ['0:100000:65536'],
      gidmap: ['0:100000:65536']
    )
  end
end
