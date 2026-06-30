# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::OomPrevention do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_notification_templates!
    ensure_mailer_available!
    allow(NotificationTemplate).to receive(:send_email!).and_return(build_mail_log_double)
  end

  def create_vps!
    build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
  end

  def reset_routing!(user)
    EventRouteMatch.delete_all
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    NotificationTarget.where(user:).delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
  end

  def fire_prevention(vps, action)
    described_class.fire2(
      kwargs: {
        vps:,
        action:,
        ooms_in_period: 12,
        period_seconds: 600
      }
    )
  end

  it 'uses Vps::Restart for restart actions' do
    vps = create_vps!

    chain, prevention = fire_prevention(vps, :restart)
    classes = tx_classes(chain)

    expect(prevention).to be_persisted
    expect(classes).to include(Transactions::Vps::Restart, Transactions::EventDelivery::Notify)
    expect(classes.index(Transactions::Vps::Restart)).to be < classes.index(Transactions::EventDelivery::Notify)
  end

  it 'does not let stale long custom e-mail labels block restart actions' do
    vps = create_vps!
    reset_routing!(vps.user)
    receiver = NotificationReceiver.create!(user: vps.user, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value: 'custom@example.test'
    )
    long_target = "#{'a' * 287}@example.test"
    action.notification_target.update_columns(target_value: long_target)
    EventRoute.create!(
      user: vps.user,
      notification_receiver: receiver,
      event_type: 'vps.oom_prevention'
    )

    chain, = fire_prevention(vps, :restart)
    event = Event.where(event_type: 'vps.oom_prevention').order(:id).last
    delivery = event.event_deliveries.sole

    expect(tx_classes(chain)).to include(Transactions::Vps::Restart)
    expect(delivery.target_value).to eq(long_target)
    expect(delivery.target_label.length).to eq(255)
  end

  it 'uses Vps::Stop for stop actions' do
    vps = create_vps!

    chain, prevention = fire_prevention(vps, :stop)
    classes = tx_classes(chain)

    expect(prevention).to be_persisted
    expect(classes).to include(Transactions::Vps::Stop, Transactions::EventDelivery::Notify)
    expect(classes.index(Transactions::Vps::Stop)).to be < classes.index(Transactions::EventDelivery::Notify)
  end

  it 'raises for invalid actions' do
    vps = create_vps!

    expect do
      fire_prevention(vps, :suspend)
    end.to raise_error(ArgumentError, 'unknown action :suspend')
  end

  it 'creates an OomPrevention row and sends prevention mail' do
    vps = create_vps!

    expect do
      fire_prevention(vps, :restart)
    end.to change(OomPrevention, :count).by(1)

    prevention = OomPrevention.last
    expect(prevention.vps).to eq(vps)
    expect(prevention.action).to eq('restart')
    expect(NotificationTemplate).to have_received(:send_email!).with(
      :vps_oom_prevention,
      hash_including(
        user: vps.user,
        vars: hash_including(
          vps:,
          action: :restart,
          ooms_in_period: 12,
          period_seconds: 600
        )
      )
    )
  end
end
