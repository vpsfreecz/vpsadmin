# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::EventDelivery do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  before do
    reset_routing!(SpecSeed.user)
  end

  def reset_routing!(user)
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
  end

  def create_webhook_delivery!(url: 'https://webhook.example/events', secret: nil)
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec webhook',
      target_kind: :custom,
      target_value: url,
      secret:
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )
    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec event',
      parameters: { note: 'from task spec' }
    )

    [event.event_deliveries.sole, action, route]
  end

  it 'posts signed webhook payloads and marks deliveries sent' do
    delivery, action, route = create_webhook_delivery!(secret: 'super-secret')
    request = nil
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '202', body: 'accepted')

    allow(Resolv).to receive(:getaddresses)
      .with('webhook.example')
      .and_return(['93.184.216.34'])
    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('webhook.example')
      expect(port).to eq(443)
      expect(options).to include(
        ipaddr: '93.184.216.34',
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 15
      )

      block.call(http)
    end
    allow(http).to receive(:request) do |req|
      request = req
      response
    end

    task.deliver_webhooks

    body = JSON.parse(request.body)
    expected_signature = OpenSSL::HMAC.hexdigest('sha256', action.secret, request.body)

    expect(body.dig('event', 'type')).to eq('user.test_notification')
    expect(body.dig('delivery', 'id')).to eq(delivery.id)
    expect(body.dig('delivery', 'route', 'id')).to eq(route.id)
    expect(request['X-Hub-Signature-256']).to eq("sha256=#{expected_signature}")
    expect(delivery.reload).to be_sent_state
    expect(delivery.response_status).to eq(202)
    expect(delivery.response_body).to eq('accepted')
    expect(delivery.attempt_count).to eq(1)
  end

  it 'does not call private webhook addresses by default' do
    delivery, = create_webhook_delivery!(url: 'http://127.0.0.1:9292/events')

    allow(Resolv).to receive(:getaddresses)
      .with('127.0.0.1')
      .and_return(['127.0.0.1'])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_queued_state
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('private address')
  end

  it 'does not call IPv4-mapped private webhook addresses' do
    delivery, = create_webhook_delivery!(url: 'https://webhook.example/events')

    allow(Resolv).to receive(:getaddresses)
      .with('webhook.example')
      .and_return(['::ffff:127.0.0.1'])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_queued_state
    expect(delivery.error_summary).to include('private address')
  end
end
