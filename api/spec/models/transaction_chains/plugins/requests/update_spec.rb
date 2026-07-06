# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin update chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Update }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
  end

  it 'updates attributes, resets state, increments mail id, and threads replies' do
    ensure_request_notification_template!('request_update_user', 'request_update_user')
    ensure_request_notification_template!('request_update_admin', 'request_update_admin')
    request = build_change_request!(
      state: :pending_correction,
      last_mail_id: 5,
      full_name: 'Old Name'
    )

    chain, = chain_class.fire2(args: [request, {
                                 full_name: 'New Name',
                                 change_reason: 'Updated reason'
                               }])

    request.reload
    expect(request.full_name).to eq('New Name')
    expect(request.change_reason).to eq('Updated reason')
    expect(request.state).to eq('awaiting')
    expect(request.last_mail_id).to eq(6)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['ChangeRequest', request.id]
    )

    event = request_events('request.updated', request).sole
    user_delivery = event.event_deliveries.detect do |delivery|
      delivery.event_routing_context&.user_id == request.user_id
    end
    admin_delivery = event.event_deliveries.detect do |delivery|
      delivery.event_routing_context&.user_id == SpecSeed.admin.id
    end

    expect(event.user).to eq(request.user)
    expect(event.parameters).to include(
      'action' => 'update',
      'request_type' => 'change',
      'request_state' => 'awaiting',
      'recipient_email' => request.user_mail,
      'mail_id' => 6,
      'reply_to_mail_id' => 5
    )
    expect(event.parameters).not_to have_key('role')
    expect(user_delivery).to be_present
    expect(admin_delivery).to be_present

    {
      user_delivery => 'request_update_user',
      admin_delivery => 'request_update_admin'
    }.each do |delivery, template_name|
      mail = delivery.mail_log

      expect(delivery.template_name).to eq(template_name)
      expect(mail.notification_template.name).to eq(template_name)
      expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-6@vpsadmin.vpsfree.cz>")
      expect(mail.in_reply_to).to eq("<vpsadmin-request-#{request.id}-5@vpsadmin.vpsfree.cz>")
      expect(mail.references).to eq("<vpsadmin-request-#{request.id}-5@vpsadmin.vpsfree.cz>")
    end
  end

  it 'routes public registration correction mail without a request user' do
    ensure_request_notification_template!('request_update_user', 'request_update_user')
    ensure_request_notification_template!('request_update_admin', 'request_update_admin')
    request = build_registration_request!(
      user: nil,
      state: :pending_correction,
      last_mail_id: 4,
      email: 'public-registration-update@test.invalid',
      full_name: 'Old Public Name'
    )

    chain, = chain_class.fire2(args: [request, {
                                 full_name: 'New Public Name'
                                 }])
    request.reload
    event = request_events('request.updated', request).sole
    delivery = event.event_deliveries.find(&:direct_email_delivery?)
    mail = delivery.mail_log

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(request.full_name).to eq('New Public Name')
    expect(event.user).to be_nil
    expect(delivery).to be_direct_email_delivery
    expect(delivery.target_value).to eq('public-registration-update@test.invalid')
    expect(delivery.template_name).to eq('request_update_user')
    expect(mail.to).to include('public-registration-update@test.invalid')
    expect(mail.message_id).to eq("<vpsadmin-request-#{request.id}-5@vpsadmin.vpsfree.cz>")
    expect(mail.in_reply_to).to eq("<vpsadmin-request-#{request.id}-4@vpsadmin.vpsfree.cz>")
  end

  def request_events(event_type, request)
    Event.where(
      event_type:,
      source_class: request.class.name,
      source_id: request.id
    ).order(:id).to_a
  end
end
