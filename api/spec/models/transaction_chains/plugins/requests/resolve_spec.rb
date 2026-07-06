# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin resolve chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Resolve }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
  end

  it 'updates resolution fields, uses fallback templates, and calls the request action' do
    ensure_request_notification_template!('request_resolve_user_approved', 'request_resolve_user_approved')
    ensure_request_notification_template!('request_resolve_admin_approved', 'request_resolve_admin_approved')
    request = build_change_request!(last_mail_id: 2)
    action_call = nil
    params = { full_name: 'Resolved Name' }

    request.define_singleton_method(:approve) do |chain, action_params|
      action_call = [chain, action_params]
    end

    chain, = chain_class.fire2(args: [request, :approved, :approve, 'Looks good', params])

    request.reload
    expect(request.state).to eq('approved')
    expect(request.admin).to eq(SpecSeed.admin)
    expect(request.admin_response).to eq('Looks good')
    expect(request.last_mail_id).to eq(3)
    expect(request.full_name).to eq('Resolved Name')
    expect(action_call).to eq([chain, params])

    event = request_events('request.resolved', request).sole
    user_delivery = event.event_deliveries.detect do |delivery|
      delivery.event_routing_context&.user_id == request.user_id
    end
    admin_delivery = event.event_deliveries.detect do |delivery|
      delivery.event_routing_context&.user_id == SpecSeed.admin.id
    end

    expect(event.parameters).to include(
      'action' => 'resolve',
      'request_type' => 'change',
      'request_state' => 'approved',
      'recipient_email' => request.user_mail,
      'reason' => 'Looks good',
      'mail_id' => 3,
      'reply_to_mail_id' => 2
    )
    expect(event.parameters).not_to have_key('role')
    expect(user_delivery).to be_present
    expect(admin_delivery).to be_present

    {
      user_delivery => 'request_resolve_user_approved',
      admin_delivery => 'request_resolve_admin_approved'
    }.each do |delivery, template_name|
      mail = delivery.mail_log

      expect(delivery.template_name).to eq(template_name)
      expect(mail.notification_template.name).to eq(template_name)
      expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
      expect(mail.in_reply_to).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
      expect(mail.references).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
    end
  end

  it 'skips user mail for ignored requests but still notifies admins' do
    ensure_request_notification_template!('request_resolve_admin_ignored', 'request_resolve_admin_ignored')
    request = build_change_request!(last_mail_id: 1)

    chain_class.fire2(args: [request, :ignored, :ignore, 'Duplicate', {}])

    request.reload
    expect(request.state).to eq('ignored')
    expect(request.admin_response).to eq('Duplicate')
    expect(request.last_mail_id).to eq(2)

    event = request_events('request.resolved', request).sole
    expect(event.user).to be_nil
    expect(event.parameters).not_to have_key('role')
    expect(event.parameters).not_to have_key('recipient_email')
    expect(event.event_deliveries.none?(&:direct_email_delivery?)).to be(true)
    expect(event.event_deliveries.sole.recipient_user).to eq(SpecSeed.admin)
    expect(event.event_deliveries.sole.mail_log.notification_template.name).to eq('request_resolve_admin_ignored')
  end

  it 'routes public registration resolve mail without a request user' do
    ensure_request_notification_template!('request_resolve_user_denied', 'request_resolve_user_denied')
    ensure_request_notification_template!('request_resolve_admin_denied', 'request_resolve_admin_denied')
    request = build_registration_request!(
      user: nil,
      last_mail_id: 2,
      email: 'public-registration-resolve@test.invalid'
    )

    chain, = chain_class.fire2(args: [request, :denied, :deny, 'No thanks', {}])
    request.reload
    event = request_events('request.resolved', request).sole
    delivery = event.event_deliveries.find(&:direct_email_delivery?)
    mail = delivery.mail_log

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(request.state).to eq('denied')
    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'request_state' => 'denied',
      'reason' => 'No thanks',
      'recipient_email' => 'public-registration-resolve@test.invalid'
    )
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_value).to eq('public-registration-resolve@test.invalid')
    expect(delivery.template_name).to eq('request_resolve_user_denied')
    expect(mail.to).to include('public-registration-resolve@test.invalid')
    expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
    expect(mail.in_reply_to).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
  end

  def request_events(event_type, request)
    Event.where(
      event_type:,
      source_class: request.class.name,
      source_id: request.id
    ).order(:id).to_a
  end
end
