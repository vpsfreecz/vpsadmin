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

  it 'concerns the request and routes applicant/admin mail with concrete templates' do
    ensure_request_notification_template!('request_create_user', 'request_create_user')
    ensure_request_notification_template!('request_create_admin', 'request_create_admin')
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

    event = request_events('request.created', request).sole
    deliveries = event.event_deliveries.to_a
    direct_delivery = deliveries.find(&:direct_email_delivery?)
    admin_deliveries = deliveries.select(&:event_routing_context)
    enabled_admin_deliveries = admin_deliveries.select(&:prepared_state?)
    skipped_admin_deliveries = admin_deliveries.select(&:skipped_state?)

    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'action' => 'create',
      'request_type' => 'registration',
      'request_state' => 'awaiting',
      'recipient_email' => request.user_mail,
      'mail_id' => 3
    )
    expect(event.parameters).not_to have_key('role')
    expect(direct_delivery).to have_attributes(
      target_value: request.user_mail,
      template_name: 'request_create_user'
    )
    expect(direct_delivery.mail_log).to have_attributes(
      message_id: "<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>"
    )
    expect(direct_delivery.mail_log.notification_template.name).to eq('request_create_user')
    expect(direct_delivery.mail_log.to).to include(request.user_mail)

    expect(enabled_admin_deliveries.map(&:recipient_user)).to contain_exactly(SpecSeed.admin, admin2)
    enabled_admin_deliveries.each do |delivery|
      expect(delivery).to be_prepared_state
      expect(delivery.mail_log.notification_template.name).to eq('request_create_admin')
      expect(delivery.mail_log.message_id).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
    end
    expect(skipped_admin_deliveries.map(&:recipient_user)).to include(disabled_admin, disabled_same_email)
  end

  it 'routes public registration owner mail without a request user' do
    ensure_request_notification_template!('request_create_user', 'request_create_user')
    ensure_request_notification_template!('request_create_admin', 'request_create_admin')
    request = build_registration_request!(
      user: nil,
      last_mail_id: 7,
      email: 'public-registration-owner@test.invalid'
    )

    chain, = chain_class.fire2(args: [request])
    event = request_events('request.created', request).sole
    delivery = event.event_deliveries.find(&:direct_email_delivery?)
    mail = delivery.mail_log

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(event.user).to be_nil
    expect(event).to be_routed_routing_state
    expect(delivery).to be_prepared_state
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_value).to eq('public-registration-owner@test.invalid')
    expect(delivery.template_name).to eq('request_create_user')
    expect(mail.to).to include('public-registration-owner@test.invalid')
    expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-7@vpsadmin.vpsfree.cz>")
    expect(VpsAdmin::API::Events.template_options_for(event.reload).fetch(:vars).fetch(:request)).to eq(request)
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
    event = request_events('request.created', request).sole

    expect(chain).to be_nil.or have_attributes(transactions: be_empty)
    expect(event.event_deliveries.map(&:state)).to all(eq('failed'))
    expect(event.event_deliveries.map(&:error_summary)).to all(
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
