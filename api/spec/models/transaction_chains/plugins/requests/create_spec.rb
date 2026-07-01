# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin create chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Create }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
  end

  it 'concerns the request and routes user/admin mail with type fallback' do
    ensure_request_notification_template!('request_create_user', 'request_action_role')
    ensure_request_notification_template!('request_create_admin', 'request_action_role')
    admin2 = create_lifecycle_user!(login: 'plugin-request-admin')
    admin2.update!(level: 99)
    disabled_admin = create_lifecycle_user!(login: 'plugin-request-muted')
    disabled_admin.update!(level: 99)
    mute_default_notifications_for!(disabled_admin)
    disabled_same_email = create_lifecycle_user!(
      login: 'plugin-request-muted-shared',
      email: SpecSeed.admin.email
    )
    disabled_same_email.update!(level: 99)
    mute_default_notifications_for!(disabled_same_email)
    request = build_registration_request!(last_mail_id: 3)

    chain, = chain_class.fire2(args: [request])

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['RegistrationRequest', request.id]
    )
    expect(tx_classes(chain)).to all(eq(Transactions::EventDelivery::Notify))

    events = request_events('request.created', request)
    user_event = events.find { |event| event.parameters.fetch('role') == 'user' }
    admin_events = events.select { |event| event.parameters.fetch('role') == 'admin' }
    enabled_admin_events = admin_events.select(&:routed_routing_state?)
    muted_admin_event = admin_events.find { |event| event.user == disabled_admin }

    expect(user_event.user).to eq(request.user)
    expect(user_event.parameters).to include(
      'action' => 'create',
      'request_type' => 'registration',
      'request_state' => 'awaiting',
      'recipient_email' => request.user_mail,
      'mail_id' => 3
    )
    expect(user_event.event_deliveries.sole).to have_attributes(
      target_value: request.user_mail,
      template_name: 'request_action_role'
    )
    expect(user_event.event_deliveries.sole.mail_log).to have_attributes(
      message_id: "<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>"
    )
    expect(user_event.event_deliveries.sole.mail_log.notification_template.name).to eq('request_create_user')
    expect(user_event.event_deliveries.sole.mail_log.to).to include(request.user_mail)

    expect(enabled_admin_events.map(&:user)).to contain_exactly(SpecSeed.admin, admin2)
    enabled_admin_events.each do |event|
      delivery = event.event_deliveries.sole
      expect(delivery).to be_prepared_state
      expect(delivery.mail_log.notification_template.name).to eq('request_create_admin')
      expect(delivery.mail_log.message_id).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
    end
    expect(admin_events.map(&:user)).not_to include(disabled_same_email)
    expect(muted_admin_event).to be_suppressed_routing_state
    expect(muted_admin_event.event_deliveries.sole).to be_skipped_state
  end

  it 'routes public registration owner mail without a request user' do
    ensure_request_notification_template!('request_create_user', 'request_action_role')
    ensure_request_notification_template!('request_create_admin', 'request_action_role')
    request = build_registration_request!(
      user: nil,
      last_mail_id: 7,
      email: 'public-registration-owner@test.invalid'
    )

    chain, = chain_class.fire2(args: [request])
    user_event = request_events('request.created', request).find do |event|
      event.parameters.fetch('role') == 'user'
    end
    delivery = user_event.event_deliveries.sole
    mail = delivery.mail_log

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(user_event.user).to be_nil
    expect(user_event).to be_routed_routing_state
    expect(delivery).to be_prepared_state
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_value).to eq('public-registration-owner@test.invalid')
    expect(mail.to).to include('public-registration-owner@test.invalid')
    expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-7@vpsadmin.vpsfree.cz>")
    expect(VpsAdmin::API::Events.template_options_for(user_event.reload).fetch(:vars).fetch(:request)).to eq(request)
  end

  it 'logs failed deliveries when every request template is missing' do
    NotificationTemplate.where(name: %w[
                                 request_create_user_registration
                                 request_create_admin_registration
                                 request_create_user
                                 request_create_admin
                               ]).destroy_all
    request = build_registration_request!

    chain, = chain_class.fire2(args: [request])
    events = request_events('request.created', request)

    expect(chain).to be_nil.or have_attributes(transactions: be_empty)
    expect(events).not_to be_empty
    expect(events.map { |event| event.event_deliveries.sole.state }).to all(eq('failed'))
    expect(events.map { |event| event.event_deliveries.sole.error_summary }).to all(
      include('NotificationTemplateDoesNotExist')
    )
  end

  it 'does not rehydrate another user request from event parameters' do
    other_request = build_change_request!(user: SpecSeed.other_user)
    event = VpsAdmin::API::Events.emit!(
      'request.updated',
      user: SpecSeed.user,
      subject: 'foreign request',
      route: false,
      payload: {
        role: 'user',
        action: 'update',
        request_type: 'change',
        request_state: 'awaiting',
        request_id: other_request.id
      }
    )

    expect { VpsAdmin::API::Events.template_options_for(event).fetch(:vars) }.to raise_error(
      ArgumentError,
      'request source is missing'
    )
  end

  def request_events(event_type, request)
    Event.where(
      event_type:,
      source_class: request.class.name,
      source_id: request.id
    ).order(:id).to_a
  end
end
