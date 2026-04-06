# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/copy'

RSpec.describe NodeCtld::Commands::Vps::Copy do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'as_id' => '202',
      'as_pool_name' => 'tank',
      'as_dataset' => 'tank/ct-dst/202',
      'consistent' => false,
      'network_interfaces' => true
    )
  end

  it 'passes the destination dataset to osctl copy' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct cp],
      [101, '202'],
      pool: 'tank',
      dataset: 'tank/ct-dst/202',
      consistent: false,
      network_interfaces: true
    )
  end

  it 'rolls back using the destination pool and container id' do
    allow(cmd).to receive(:osctl_pool).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl_pool).with(
      'tank',
      %i[ct del],
      '202',
      { force: true },
      {},
      valid_rcs: [1]
    )
  end
end
