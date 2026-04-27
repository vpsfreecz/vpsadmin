# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsMigration do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:fixture) { create_vps_migration_fixture!(count: 1) }
  let(:vps) { fixture.fetch(:vpses).first }
  let(:dst_node) { fixture.fetch(:dst_node) }

  def create_plan!(state:)
    create_migration_plan!(dst_node: dst_node, state: state)
  end

  def create_existing_migration!(plan_state:, migration_state: :queued)
    plan = create_plan!(state: plan_state)
    build_vps_migration!(
      plan: plan,
      vps: vps,
      state: migration_state,
      transaction_chain: build_active_chain!
    )
  end

  shared_examples 'rejects duplicate migrations' do |plan_state|
    it "rejects a duplicate when the existing plan is #{plan_state}" do
      create_existing_migration!(plan_state: plan_state)

      duplicate = build_unsaved_vps_migration(
        plan: create_plan!(state: :staged),
        vps: vps,
        transaction_chain: build_active_chain!
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:vps]).to include('is already in a migration plan')
    end
  end

  %i[staged running cancelling failing].each do |plan_state|
    it_behaves_like 'rejects duplicate migrations', plan_state
  end

  %i[cancelled done error].each do |plan_state|
    it "allows a duplicate when the existing plan is #{plan_state}" do
      create_existing_migration!(plan_state: plan_state, migration_state: :done)

      duplicate = build_unsaved_vps_migration(
        plan: create_plan!(state: :staged),
        vps: vps,
        transaction_chain: build_active_chain!
      )

      expect(duplicate).to be_valid
    end
  end

  it 'allows a duplicate after the existing migration row is terminal' do
    create_existing_migration!(plan_state: :running, migration_state: :cancelled)

    duplicate = build_unsaved_vps_migration(
      plan: create_plan!(state: :staged),
      vps: vps,
      transaction_chain: build_active_chain!
    )

    expect(duplicate).to be_valid
  end

  it 'aliases maintenance_window to outage_window' do
    migration = build_unsaved_vps_migration(
      plan: create_plan!(state: :staged),
      vps: vps
    )

    migration.maintenance_window = true
    expect(migration.outage_window).to be(true)

    migration.outage_window = false
    expect(migration.maintenance_window).to be(false)
  end
end
