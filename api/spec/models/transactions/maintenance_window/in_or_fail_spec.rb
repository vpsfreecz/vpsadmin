# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Transactions::MaintenanceWindow::InOrFail do
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

  it 'uses the general queue' do
    tx = fire_transaction(args: [vps, 15])

    expect(tx.queue).to eq('general')
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
    create_maintenance_window!(vps: vps, weekday: 5, is_open: true, opens_at: 300, closes_at: 420)
    create_maintenance_window!(vps: vps, weekday: 3, is_open: true, opens_at: 120, closes_at: 240)
    create_maintenance_window!(vps: vps, weekday: 1, is_open: false)

    tx = fire_transaction(args: [vps, 45])
    payload = JSON.parse(tx.input).fetch('input')

    expect(payload.fetch('reserve_time')).to eq(45)
    expect(payload.fetch('windows')).to eq([
                                             { 'weekday' => 3, 'opens_at' => 120, 'closes_at' => 240 },
                                             { 'weekday' => 5, 'opens_at' => 300, 'closes_at' => 420 }
                                           ])
  end
end
