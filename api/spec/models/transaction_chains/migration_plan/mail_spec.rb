# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::MigrationPlan::Mail do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_available_node_status!(SpecSeed.node)
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
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

  it 'sends mail only for migration users with mailer enabled' do
    plan, vpses = create_plan_with_user_migrations!
    mail_user = vpses.first.user
    vpses.last.user.update!(mailer_enabled: false)

    chain, = described_class.fire(plan)

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['MigrationPlan', plan.id]
    )
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_migration_planned,
      hash_including(user: mail_user)
    ).once
  end

  it 'remains empty when no migration user has mailer enabled' do
    plan, vpses = create_plan_with_user_migrations!
    vpses.each { |vps| vps.user.update!(mailer_enabled: false) }

    chain, = described_class.fire(plan)

    expect(chain).to be_nil
    expect(MailTemplate).not_to have_received(:send_mail!)
  end
end
