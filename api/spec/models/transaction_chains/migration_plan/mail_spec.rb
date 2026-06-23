# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::MigrationPlan::Mail do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_notification_templates!
    ensure_available_node_status!(SpecSeed.node)
    ensure_mailer_available!
  end

  def create_plan_with_user_migrations!
    fixture = create_vps_migration_fixture!(
      count: 2,
      users: [SpecSeed.user, SpecSeed.other_user]
    )
    plan = create_migration_plan!(
      dst_node: fixture.fetch(:dst_node),
      concurrency: 2,
      send_mail: true
    )

    fixture.fetch(:vpses).each do |vps|
      build_vps_migration!(
        plan: plan,
        vps: vps,
        transaction_chain: build_active_chain!
      )
    end

    [plan, fixture.fetch(:vpses)]
  end

  it 'routes migration events and queues mail only for users with unmuted default notifications' do
    plan, vpses = create_plan_with_user_migrations!
    mail_user = vpses.first.user
    mute_default_notifications_for!(vpses.last.user)

    chain, = described_class.fire(plan)
    events = Event.where(event_type: 'vps.migration_planned').order(:id)
    routed_event = events.find(&:routed_routing_state?)
    suppressed_event = events.find(&:suppressed_routing_state?)

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['MigrationPlan', plan.id]
    )
    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(events.size).to eq(2)
    expect(routed_event.user).to eq(mail_user)
    expect(routed_event.event_deliveries.sole).to be_prepared_state
    expect(suppressed_event.user).to eq(vpses.last.user)
    expect(suppressed_event.event_deliveries.sole).to be_skipped_state
  end

  it 'logs suppressed events and remains empty when all migration users are muted' do
    plan, vpses = create_plan_with_user_migrations!
    vpses.each { |vps| mute_default_notifications_for!(vps.user) }

    chain, = described_class.fire(plan)
    events = Event.where(event_type: 'vps.migration_planned').order(:id)

    expect(chain).to be_nil
    expect(events.size).to eq(2)
    expect(events).to all(be_suppressed_routing_state)
    expect(events.flat_map(&:event_deliveries)).to all(be_skipped_state)
  end
end
