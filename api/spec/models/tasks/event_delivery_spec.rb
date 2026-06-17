# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::EventDelivery do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  before do
    unlock_transaction_signer!
    ensure_mailer_available!
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

  def create_email_delivery!(target_kind: :default_recipient, target_value: nil)
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec e-mail',
      target_kind:,
      target_value:
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )
    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec e-mail event',
      parameters: { note: 'from e-mail task spec' }
    )

    [event.event_deliveries.sole, action, route]
  end

  def create_direct_request_email_delivery!
    event = VpsAdmin::API::Events.emit!(
      'request.created',
      subject: 'Spec public registration',
      parameters: {
        role: 'user',
        action: 'create',
        request_type: 'registration',
        request_state: 'pending',
        recipient_email: 'public-registration@example.test',
        mail_id: 1
      }
    )

    event.event_deliveries.sole
  end

  def create_vps_email_delivery!
    VpsAdmin::API::MailTemplates.install_defaults!
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec VPS receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec VPS e-mail',
      target_kind: :default_recipient
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'vps.suspended'
    )
    event = VpsAdmin::API::Events.emit!(
      'vps.suspended',
      user: SpecSeed.user,
      vps:,
      subject: 'Spec VPS suspended',
      parameters: {
        state: 'suspended',
        reason: 'spec reason'
      }
    )

    [event.event_deliveries.sole, action, route, vps]
  end

  def create_dataset_migration_email_delivery!(export_count:)
    VpsAdmin::API::MailTemplates.install_defaults!
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec storage receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec storage e-mail',
      target_kind: :default_recipient
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'dataset.migration_begun'
    )
    event = VpsAdmin::API::Events.emit!(
      'dataset.migration_begun',
      user: SpecSeed.user,
      subject: 'Spec dataset migration',
      parameters: {
        dataset_id: 123,
        dataset_full_name: 'tank/spec',
        user_id: SpecSeed.user.id,
        user_login: SpecSeed.user.login,
        user_name: SpecSeed.user.full_name,
        src_pool_id: 1,
        src_pool_filesystem: 'src-pool',
        dst_pool_id: 2,
        dst_pool_filesystem: 'dst-pool',
        export_count: export_count,
        affected_vps_count: 1,
        affected_vpses: [
          { id: 42, hostname: 'sample-vps' }
        ],
        restart_vps: true,
        maintenance_window: false
      }
    )

    [event.event_deliveries.sole, action, route]
  end

  it 'queues planned e-mail deliveries through mail transactions' do
    delivery, action, route = create_email_delivery!

    expect do
      task.deliver_emails
    end.to change(Transaction, :count).by(1)

    delivery.reload
    transaction = delivery.delivery_transaction

    expect(delivery).to be_queued_state
    expect(delivery.notification_receiver_action).to eq(action)
    expect(delivery.event_route).to eq(route)
    expect(delivery.mail_log).to be_present
    expect(delivery.mail_log.to).to eq(SpecSeed.user.email)
    expect(delivery.mail_log.subject).to eq('Spec e-mail event')
    expect(Transaction.for_type(transaction.handle)).to eq(Transactions::Mail::Send)
    expect(delivery.attempt_count).to eq(1)
  end

  it 'resolves default e-mail recipients when the delivery is queued' do
    delivery, = create_email_delivery!
    SpecSeed.user.update!(email: 'changed-default@example.test')

    task.deliver_emails

    delivery.reload
    expect(delivery.target_value).to eq('default')
    expect(delivery.target_label).to eq('Default recipient')
    expect(delivery.mail_log.to).to eq('changed-default@example.test')
  end

  it 'fails delayed VPS e-mail rendering when the VPS no longer belongs to the event user' do
    delivery, = create_vps_email_delivery!
    delivery.event.vps.update_column(:user_id, SpecSeed.other_user.id)

    expect do
      expect do
        task.deliver_emails
      end.not_to change(Transaction, :count)
    end.not_to change(MailLog, :count)

    delivery.reload

    expect(delivery).to be_failed_state
    expect(delivery.mail_log).to be_nil
    expect(delivery.error_summary).to include('VPS does not belong to event user')
  end

  it 'clamps delayed dataset migration fallback collection sizes' do
    delivery, = create_dataset_migration_email_delivery!(export_count: 1_000_000)

    expect do
      task.deliver_emails
    end.to change(Transaction, :count).by(1)

    delivery.reload

    expect(delivery).to be_queued_state
    expect(delivery.mail_log.text_plain).to include('Exports: 100')
    expect(delivery.mail_log.text_plain).to include('Affected VPS: #42 sample-vps')
  end

  it 'retries e-mail deliveries when no mail server is available' do
    delivery, = create_email_delivery!
    Node.update_all(active: false)

    expect do
      expect do
        task.deliver_emails
      end.not_to change(Transaction, :count)
    end.not_to change(MailLog, :count)

    delivery.reload

    expect(delivery).to be_queued_state
    expect(delivery.mail_log).to be_nil
    expect(delivery.transaction_id).to be_nil
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('ActiveRecord::RecordNotFound')
    expect(delivery.attempt_count).to eq(1)
  end

  it 'retries direct e-mail deliveries when no mail server is available' do
    delivery = create_direct_request_email_delivery!
    Node.update_all(active: false)

    expect(delivery).to be_direct_email_delivery

    expect do
      expect do
        task.deliver_emails
      end.not_to change(Transaction, :count)
    end.not_to change(MailLog, :count)

    delivery.reload

    expect(delivery).to be_queued_state
    expect(delivery.mail_log).to be_nil
    expect(delivery.transaction_id).to be_nil
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('ActiveRecord::RecordNotFound')
    expect(delivery.attempt_count).to eq(1)
  end

  it 'marks queued e-mail deliveries sent after the mail transaction succeeds' do
    delivery, = create_email_delivery!

    task.deliver_emails
    delivery.reload.delivery_transaction.update_columns(
      done: Transaction.dones[:done],
      status: 1
    )

    task.deliver_emails

    expect(delivery.reload).to be_sent_state
  end

  it 'marks queued e-mail deliveries failed after the mail transaction fails' do
    delivery, = create_email_delivery!

    task.deliver_emails
    delivery.reload.delivery_transaction.update_columns(
      done: Transaction.dones[:done],
      status: 0
    )

    task.deliver_emails

    expect(delivery.reload).to be_failed_state
    expect(delivery.error_summary).to include('mail transaction failed')
  end

  it 'does not queue e-mail deliveries for disabled receivers' do
    delivery, = create_email_delivery!
    delivery.notification_receiver.update!(enabled: false)

    expect do
      task.deliver_emails
    end.not_to change(Transaction, :count)

    expect(delivery.reload).to be_canceled_state
    expect(delivery.error_summary).to include('receiver')
  end

  it 'does not treat receiver-backed e-mail deliveries as direct after receiver deletion' do
    delivery, = create_email_delivery!
    delivery.notification_receiver.destroy!

    expect do
      task.deliver_emails
    end.not_to change(Transaction, :count)

    delivery.reload

    expect(delivery.notification_receiver).to be_nil
    expect(delivery.notification_receiver_action).to be_nil
    expect(delivery).not_to be_direct_email_delivery
    expect(delivery).to be_canceled_state
    expect(delivery.error_summary).to include('receiver')
  end

  it 'does not queue e-mail deliveries for disabled actions' do
    delivery, action = create_email_delivery!
    action.update!(enabled: false)

    expect do
      task.deliver_emails
    end.not_to change(Transaction, :count)

    expect(delivery.reload).to be_canceled_state
    expect(delivery.error_summary).to include('action')
  end

  it 'uses custom e-mail action targets without adding the account e-mail' do
    delivery, = create_email_delivery!(
      target_kind: :custom,
      target_value: 'custom@example.test'
    )

    task.deliver_emails

    expect(delivery.reload.mail_log.to).to eq('custom@example.test')
  end

  it 'uses the snapshotted e-mail target when the action is edited later' do
    delivery, action = create_email_delivery!(
      target_kind: :custom,
      target_value: 'old-target@example.test'
    )
    action.update!(target_value: 'new-target@example.test')

    task.deliver_emails

    expect(delivery.reload.mail_log.to).to eq('old-target@example.test')
  end

  it 'does not render OOM reports that belong to another user' do
    foreign_vps = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)
    foreign_report = create_oom_report_fixture!(vps: foreign_vps, killed_name: 'foreign-process')
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec e-mail',
      target_kind: :default_recipient
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'vps.oom_report'
    )
    event = VpsAdmin::API::Events.emit!(
      'vps.oom_report',
      user: SpecSeed.user,
      subject: 'Foreign OOM report',
      parameters: {
        selected_report_ids: [foreign_report.id]
      }
    )
    delivery = event.event_deliveries.sole

    expect do
      task.deliver_emails
    end.not_to change(Transaction, :count)

    expect(delivery.reload).to be_failed_state
    expect(delivery.error_summary).to include('missing report ids')
    expect(delivery.mail_log).to be_nil
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

  it 'claims webhook deliveries exclusively across stale worker reads' do
    delivery, = create_webhook_delivery!(url: 'https://webhook.example/events')
    stale_delivery = EventDelivery.find(delivery.id)

    expect(task.send(:claim_webhook_delivery, delivery)).to be(true)
    expect(task.send(:claim_webhook_delivery, stale_delivery)).to be(false)

    expect(delivery.reload).to be_queued_state
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.next_attempt_at).to be > Time.now
  end

  it 'posts webhooks to the snapshotted target when the action is edited later' do
    delivery, action = create_webhook_delivery!(url: 'https://webhook.example/events')
    action.update!(target_value: 'https://changed.example/events')
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '204', body: '')

    allow(Resolv).to receive(:getaddresses)
      .with('webhook.example')
      .and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses)
      .with('changed.example')
      .and_raise('changed target should not be resolved')
    allow(Net::HTTP).to receive(:start) do |host, _port, **_options, &block|
      expect(host).to eq('webhook.example')
      block.call(http)
    end
    allow(http).to receive(:request).and_return(response)

    task.deliver_webhooks

    expect(delivery.reload).to be_sent_state
    expect(Resolv).not_to have_received(:getaddresses).with('changed.example')
  end

  it 'does not retry webhook deliveries for muted receivers' do
    delivery, = create_webhook_delivery!(url: 'https://webhook.example/events')
    delivery.update!(state: :queued, attempt_count: 1)
    delivery.notification_receiver.update!(mute: true)

    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_canceled_state
    expect(delivery.error_summary).to include('receiver')
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
