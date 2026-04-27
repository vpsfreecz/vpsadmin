# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Transactions::MaintenanceWindow::Wait do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:fixture) { create_vps_migration_fixture!(count: 1) }
  let(:vps) { fixture.fetch(:vpses).first }
  let(:node) { fixture.fetch(:dst_node) }

  def fire_transaction(args:, kwargs: {})
    described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: args,
      kwargs: kwargs
    )
  end

  it 'uses the outage queue' do
    tx = fire_transaction(args: [vps, 15])

    expect(tx.queue).to eq('outage')
  end

  it 'uses an explicit node when provided' do
    tx = fire_transaction(args: [vps, 15], kwargs: { node: node })

    expect(tx.node_id).to eq(node.id)
  end

  it 'uses the VPS node by default' do
    tx = fire_transaction(args: [vps, 15])

    expect(tx.node_id).to eq(vps.node_id)
  end

  it 'serializes ordered maintenance windows and reserve time' do
    create_maintenance_window!(vps: vps, weekday: 4, is_open: true, opens_at: 120, closes_at: 240)
    create_maintenance_window!(vps: vps, weekday: 2, is_open: true, opens_at: 60, closes_at: 180)
    create_maintenance_window!(vps: vps, weekday: 1, is_open: false)

    tx = fire_transaction(args: [vps, 30])
    payload = JSON.parse(tx.input).fetch('input')

    expect(payload.fetch('reserve_time')).to eq(30)
    expect(payload.fetch('windows')).to eq([
                                             { 'weekday' => 2, 'opens_at' => 60, 'closes_at' => 180 },
                                             { 'weekday' => 4, 'opens_at' => 120, 'closes_at' => 240 }
                                           ])
  end
end
