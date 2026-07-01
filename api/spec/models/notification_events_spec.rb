# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::NotificationEvents do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    reset_routing!(SpecSeed.user)
  end

  def reset_routing!(user)
    EventRouteMatch.delete_all
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
  end

  def create_webhook_route!(user)
    receiver = NotificationReceiver.create!(user:, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec webhook',
      target_kind: :custom,
      target_value: 'https://example.test/events'
    )
    route = EventRoute.create!(
      user:,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )

    [receiver, action, route]
  end

  it 'emits and releases prepared deliveries without creating a transaction chain' do
    _receiver, action, route = create_webhook_route!(SpecSeed.user)
    chain_class = Class.new(TransactionChain) do
      def link_chain(user)
        route_event!(
          'user.test_notification',
          user:,
          subject: 'Spec direct event',
          payload: { note: 'from direct runner' }
        )
      end
    end

    chain_count = TransactionChain.count
    transaction_count = Transaction.count

    expect do
      described_class.run_chain(chain_class, args: [SpecSeed.user])
    end.to change(Event, :count).by(1)

    expect(TransactionChain.count).to eq(chain_count)
    expect(Transaction.count).to eq(transaction_count)

    event = Event.order(:id).last
    delivery = event.event_deliveries.sole

    expect(event.event_type).to eq('user.test_notification')
    expect(event.subject).to eq('Spec direct event')
    expect(event.parameters).to include('note' => 'from direct runner')
    expect(event.event_route_matches.reload.map(&:event_route)).to eq([route])
    expect(delivery).to be_released_state
    expect(delivery.notification_receiver_action).to eq(action)
    expect(delivery.transaction_id).to be_nil
    expect(delivery.payload).to be_present
  end

  it 'raises when a direct notification builder appends a real transaction' do
    chain_class = Class.new(TransactionChain) do
      def link_chain
        append_t(Transactions::Utils::NoOp, args: [SpecSeed.node.id])
      end
    end

    expect do
      described_class.run_chain(chain_class)
    end.to raise_error(
      described_class::NonEventTransaction,
      /attempted to use append_t/
    )
  end

  it 'derives event attributes from typed event arguments' do
    user = create_lifecycle_user!
    auth = create_auth_cleanup_fixture!(user:)
    session = auth.fetch(:token_session)
    authorization = auth.fetch(:oauth2_authorization)

    event = VpsAdmin::API::Events.emit!(
      'user.new_login',
      session:,
      authorization:,
      route: false
    )

    expect(event.user).to eq(user)
    expect(event.source).to eq(session)
    expect(event.subject).to eq('New sign-in')
    expect(event.summary).to eq("New sign-in to #{user.login}")
    expect(event.ip_addr).to eq('127.0.0.1')
    expect(event.parameters).to include(
      'auth_type' => 'token',
      'authorization_id' => authorization.id,
      'oauth2_client_id' => authorization.oauth2_client_id
    )

    vars = VpsAdmin::API::Events.template_options_for(event).fetch(:vars)
    expect(vars).to include(
      user:,
      user_session: session,
      authorization:,
      user_device: authorization.user_device
    )
  end

  it 'validates typed event arguments before creating an event' do
    user = create_lifecycle_user!
    authorization = create_auth_cleanup_fixture!(user:).fetch(:oauth2_authorization)

    expect do
      VpsAdmin::API::Events.emit!(
        'user.new_login',
        session: user,
        authorization:,
        route: false
      )
    end.to raise_error(
      ArgumentError,
      /user\.new_login argument session must be UserSession, got User/
    )
  end
end
