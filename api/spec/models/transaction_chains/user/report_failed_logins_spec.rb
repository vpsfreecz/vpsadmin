# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::ReportFailedLogins do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_notification_templates!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'concerns every affected user, sends one mail per group, and marks attempts reported' do
    user_a = create_lifecycle_user!
    user_b = create_lifecycle_user!
    attempts_a = [
      create_failed_login!(user: user_a, created_at: 2.minutes.ago),
      create_failed_login!(user: user_a, created_at: 1.minute.ago)
    ]
    attempts_b = [create_failed_login!(user: user_b)]

    chain, = described_class.fire(
      user_a => [attempts_a],
      user_b => [attempts_b]
    )

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['User', user_a.id],
      ['User', user_b.id]
    )
    expect(tx_classes(chain).count(Transactions::EventDelivery::Notify)).to eq(2)
    event_a = expect_routed_event!('user.failed_logins', user: user_a)
    event_b = expect_routed_event!('user.failed_logins', user: user_b)
    expect(event_a.parameters).to include(
      'attempt_count' => 2,
      'group_count' => 1,
      'attempt_group_ids' => [attempts_a.map(&:id)]
    )
    expect(event_b.parameters).to include(
      'attempt_count' => 1,
      'group_count' => 1,
      'attempt_group_ids' => [attempts_b.map(&:id)]
    )
    expect(UserFailedLogin.where(id: attempts_a.concat(attempts_b).map(&:id)).where(reported_at: nil)).to be_empty
  end

  it 'does not mark attempts reported when local routed e-mail rendering fails' do
    user = create_lifecycle_user!
    attempt = create_failed_login!(user:)

    allow(NotificationTemplate).to receive(:send_email!).and_raise(ArgumentError, 'render failed')

    expect do
      described_class.fire(user => [[attempt]])
    end.to raise_error(RuntimeError, /failed-login notification was not prepared/)

    expect(attempt.reload.reported_at).to be_nil
  end

  it 'marks attempts reported when notification routing is muted' do
    user = create_lifecycle_user!
    mute_default_notifications_for!(user)
    attempt = create_failed_login!(user:)

    chain, = described_class.fire(user => [[attempt]])
    event = expect_suppressed_event!('user.failed_logins', user:)

    expect(chain).to be_nil
    expect(attempt.reload.reported_at).to be_present
    expect(event.event_deliveries.sole.error_summary).to include('does not notify')
  end
end
