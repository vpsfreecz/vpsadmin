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
      'network_interfaces' => true,
      'from_snapshot' => 'base-snapshot'
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
      network_interfaces: true,
      from_snapshot: 'base-snapshot'
    )
  end

  it 'resolves an unconfirmed snapshot name from the database' do
    db = instance_double(NodeCtld::Db, close: nil)
    rs = double(get!: { 'name' => '2026-06-13T12:00:00' })
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'as_id' => '202',
      'as_pool_name' => 'tank',
      'as_dataset' => 'tank/ct-dst/202',
      'consistent' => false,
      'network_interfaces' => true,
      'from_snapshot' => {
        'id' => 42,
        'name' => '2026-06-13T12:00:00 (unconfirmed)',
        'confirmed' => 'confirm_create'
      }
    )

    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(db).to receive(:prepared).with('SELECT name FROM snapshots WHERE id = ?', 42).and_return(rs)
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct cp],
      [101, '202'],
      hash_including(from_snapshot: '2026-06-13T12:00:00')
    )
    expect(db).to have_received(:close)
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
