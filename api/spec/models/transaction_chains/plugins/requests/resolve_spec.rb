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
    SpecSeed.admin.update!(mailer_enabled: true)
  end

  it 'updates resolution fields, uses fallback templates, and calls the request action' do
    ensure_request_notification_template!('request_resolve_user_approved', 'request_resolve_role_state')
    ensure_request_notification_template!('request_resolve_admin_approved', 'request_resolve_role_state')
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

    events = request_events('request.resolved', request)
    user_event = events.find { |event| event.parameters.fetch('role') == 'user' }

    expect(user_event.parameters).to include(
      'action' => 'resolve',
      'request_type' => 'change',
      'request_state' => 'approved',
      'recipient_email' => request.user_mail,
      'reason' => 'Looks good',
      'mail_id' => 3,
      'reply_to_mail_id' => 2
    )
    events.each do |event|
      delivery = event.event_deliveries.sole
      mail = delivery.mail_log

      expect(delivery.template_name).to eq('request_resolve_role_state')
      expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
      expect(mail.in_reply_to).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
      expect(mail.references).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
    end
  end

  it 'skips user mail for ignored requests but still notifies admins' do
    ensure_request_notification_template!('request_resolve_admin_ignored', 'request_resolve_role_state')
    request = build_change_request!(last_mail_id: 1)

    chain_class.fire2(args: [request, :ignored, :ignore, 'Duplicate', {}])

    request.reload
    expect(request.state).to eq('ignored')
    expect(request.admin_response).to eq('Duplicate')
    expect(request.last_mail_id).to eq(2)

    events = request_events('request.resolved', request)
    expect(events.none? { |event| event.parameters.fetch('role') == 'user' }).to be(true)
    expect(events.any? { |event| event.user == SpecSeed.admin }).to be(true)
    expect(events.sole.event_deliveries.sole.mail_log.notification_template.name).to eq('request_resolve_admin_ignored')
  end

  it 'routes public registration resolve mail without a request user' do
    ensure_request_notification_template!('request_resolve_user_denied', 'request_resolve_role_state')
    ensure_request_notification_template!('request_resolve_admin_denied', 'request_resolve_role_state')
    request = build_registration_request!(
      user: nil,
      last_mail_id: 2,
      email: 'public-registration-resolve@test.invalid'
    )

    chain, = chain_class.fire2(args: [request, :denied, :deny, 'No thanks', {}])
    request.reload
    user_event = request_events('request.resolved', request).find do |event|
      event.parameters.fetch('role') == 'user'
    end
    delivery = user_event.event_deliveries.sole
    mail = delivery.mail_log

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(request.state).to eq('denied')
    expect(user_event.user).to be_nil
    expect(user_event.parameters).to include(
      'request_state' => 'denied',
      'reason' => 'No thanks',
      'recipient_email' => 'public-registration-resolve@test.invalid'
    )
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_value).to eq('public-registration-resolve@test.invalid')
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
