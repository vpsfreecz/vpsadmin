# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/send_config'

RSpec.describe NodeCtld::Commands::Vps::SendConfig do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'node' => '10.0.0.2',
      'pool_name' => 'tank',
      'as_id' => '202',
      'network_interfaces' => true,
      'snapshots' => false,
      'passphrase' => 'secret',
      'from_snapshot' => 'base',
      'preexisting_datasets' => true
    )
  end

  it 'passes send options to osctl' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct send config],
      [101, '10.0.0.2'],
      hash_including(
        to_pool: 'tank',
        as_id: '202',
        network_interfaces: true,
        snapshots: false,
        passphrase: 'secret',
        from_snapshot: 'base',
        preexisting_datasets: true
      )
    )
  end

  it 'cancels the local send state on rollback' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct send cancel],
      101,
      force: true,
      local: true
    )
  end
end
