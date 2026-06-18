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
    VpsAdmin::API::MailTemplates.install_defaults!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
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
      },
      email_vars: { request: 'spec request' }
    )

    event.event_deliveries.sole
  end

  def create_direct_custom_email_delivery!
    event = VpsAdmin::API::Events.emit!(
      'incident_report.reply',
      subject: 'Re: Abuse report',
      summary: 'Created incident reports',
      parameters: {
        from_email: 'abuse@example.test',
        recipient_emails: ['sender@example.test'],
        in_reply_to_message_id: 'incident-source@example.test',
        references_message_id: 'incident-source@example.test',
        incident_count: 1,
        user_count: 1,
        vps_count: 1,
        text: "Created 1 incident reports of 1 users and 1 VPS:\n"
      }
    )

    event.event_deliveries.sole
  end

  def create_user_incident_reply_email_delivery!
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec incident receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec incident e-mail',
      target_kind: :custom,
      target_value: 'custom@example.test'
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'incident_report.reply'
    )
    event = VpsAdmin::API::Events.emit!(
      'incident_report.reply',
      user: SpecSeed.user,
      subject: 'Spoofed incident reply',
      summary: 'User-created incident reply test',
      parameters: {
        from_email: 'spoofed@example.test',
        recipient_emails: ['sender@example.test'],
        in_reply_to_message_id: 'spoofed-message@example.test',
        references_message_id: 'spoofed-message@example.test',
        text: 'spoofed body'
      }
    )

    event.event_deliveries.sole
  end

  def create_user_system_report_email_delivery!
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec report receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec report e-mail',
      target_kind: :custom,
      target_value: 'custom@example.test'
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'system.daily_report'
    )
    event = VpsAdmin::API::Events.emit!(
      'system.daily_report',
      user: SpecSeed.user,
      subject: 'User-created daily report event',
      summary: 'User-created daily report event',
      parameters: {
        language_id: SpecSeed.language.id,
        language_code: SpecSeed.language.code,
        period_start: '2026-04-01T00:00:00Z',
        period_end: '2026-04-02T00:00:00Z',
        period_seconds: 86_400
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

  def smtp_response(status = '250', body = '250 2.0.0 queued as spec-message-id')
    instance_double(Net::SMTP::Response, status:, string: body)
  end

  def stub_mail_delivery!(error = nil, response: nil)
    response ||= smtp_response

    allow(::Mail).to receive(:new).and_wrap_original do |original, *args|
      message = original.call(*args)
      allow(message).to receive(:deliver!) do
        raise error if error

        response
      end

      message
    end
  end

  it 'sends released e-mail deliveries and records the attempt' do
    delivery, action, route = create_email_delivery!
    stub_mail_delivery!

    expect do
      task.deliver_emails
    end.to change(EventDeliveryAttempt, :count).by(1)

    delivery.reload
    attempt = delivery.event_delivery_attempts.sole

    expect(delivery).to be_sent_state
    expect(delivery.notification_receiver_action).to eq(action)
    expect(delivery.event_route).to eq(route)
    expect(delivery.mail_log).to be_present
    expect(delivery.mail_log.to).to eq(SpecSeed.user.email)
    expect(delivery.mail_log.subject).to eq('Spec e-mail event')
    expect(delivery.response_status).to eq(250)
    expect(delivery.response_body).to eq('250 2.0.0 queued as spec-message-id')
    expect(delivery.attempt_count).to eq(1)
    expect(attempt).to be_succeeded_state
    expect(attempt.response_status).to eq(250)
    expect(attempt.response_body).to eq('250 2.0.0 queued as spec-message-id')
  end

  it 'snapshots default e-mail recipients when the delivery is prepared' do
    delivery, = create_email_delivery!
    original_recipient = delivery.mail_log.to
    SpecSeed.user.update!(email: 'changed-default@example.test')
    stub_mail_delivery!

    task.deliver_emails

    delivery.reload
    expect(delivery.target_value).to eq('default')
    expect(delivery.target_label).to eq('Default recipient')
    expect(delivery.mail_log.to).to eq(original_recipient)
  end

  it 'clamps delayed dataset migration fallback collection sizes' do
    delivery, = create_dataset_migration_email_delivery!(export_count: 1_000_000)
    stub_mail_delivery!

    expect do
      task.deliver_emails
    end.to change(EventDeliveryAttempt, :count).by(1)

    delivery.reload

    expect(delivery).to be_sent_state
    expect(delivery.mail_log.text_plain).to include('Exports: 100')
    expect(delivery.mail_log.text_plain).to include('Affected VPS: #42 sample-vps')
  end

  it 'retries e-mail deliveries when SMTP delivery fails' do
    delivery, = create_email_delivery!
    stub_mail_delivery!(StandardError.new('smtp rejected'))

    expect do
      expect do
        task.deliver_emails
      end.to change(EventDeliveryAttempt, :count).by(1)
    end.not_to change(Transaction, :count)

    delivery.reload

    expect(delivery).to be_released_state
    expect(delivery.mail_log).to be_present
    expect(delivery.transaction_id).to be_nil
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('StandardError: smtp rejected')
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.event_delivery_attempts.sole).to be_failed_state
  end

  it 'records SMTP error responses when e-mail delivery fails' do
    delivery, = create_email_delivery!
    response = Net::SMTP::Response.parse("550 5.1.1 recipient rejected\n")
    stub_mail_delivery!(Net::SMTPFatalError.new(response))

    expect do
      task.deliver_emails
    end.to change(EventDeliveryAttempt, :count).by(1)

    delivery.reload
    attempt = delivery.event_delivery_attempts.sole

    expect(delivery).to be_released_state
    expect(delivery.response_status).to eq(550)
    expect(delivery.response_body).to eq("550 5.1.1 recipient rejected\n")
    expect(delivery.error_summary).to include('Net::SMTPFatalError: 550 5.1.1 recipient rejected')
    expect(attempt).to be_failed_state
    expect(attempt.response_status).to eq(550)
    expect(attempt.response_body).to eq("550 5.1.1 recipient rejected\n")
  end

  it 'retries direct e-mail deliveries when SMTP delivery fails' do
    delivery = create_direct_request_email_delivery!
    stub_mail_delivery!(StandardError.new('smtp rejected'))

    expect(delivery).to be_direct_email_delivery

    expect do
      expect do
        task.deliver_emails
      end.to change(EventDeliveryAttempt, :count).by(1)
    end.not_to change(Transaction, :count)

    delivery.reload

    expect(delivery).to be_released_state
    expect(delivery.mail_log).to be_present
    expect(delivery.transaction_id).to be_nil
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('StandardError: smtp rejected')
    expect(delivery.attempt_count).to eq(1)
  end

  it 'sends direct custom e-mail deliveries with their rendered snapshot' do
    delivery = create_direct_custom_email_delivery!
    stub_mail_delivery!

    expect(delivery).to be_direct_email_delivery

    expect do
      task.deliver_emails
    end.to change(EventDeliveryAttempt, :count).by(1)

    delivery.reload

    expect(delivery).to be_sent_state
    expect(delivery.mail_log).to be_present
    expect(delivery.mail_log.from).to eq('abuse@example.test')
    expect(delivery.mail_log.to).to eq('sender@example.test')
    expect(delivery.mail_log.subject).to eq('Re: Abuse report')
    expect(delivery.mail_log.text_plain).to eq(
      "Created 1 incident reports of 1 users and 1 VPS:\n"
    )
    expect(delivery.mail_log.in_reply_to).to eq('incident-source@example.test')
    expect(delivery.mail_log.references).to eq('incident-source@example.test')
  end

  it 'ignores incident reply sender and threading parameters for user-routed e-mails' do
    delivery = create_user_incident_reply_email_delivery!
    stub_mail_delivery!

    expect(delivery).not_to be_direct_email_delivery

    task.deliver_emails

    mail_log = delivery.reload.mail_log
    expect(mail_log.from).to eq(VpsAdmin::API::MailTemplates.default_from)
    expect(mail_log.to).to eq('custom@example.test')
    expect(mail_log.text_plain).not_to eq('spoofed body')
    expect(mail_log.text_plain).to include('Event type: incident_report.reply')
    expect(mail_log.in_reply_to).to be_nil
    expect(mail_log.references).to be_nil
  end

  it 'renders user-routed system report events as generic e-mails' do
    delivery = create_user_system_report_email_delivery!
    stub_mail_delivery!

    expect(delivery).not_to be_direct_email_delivery

    task.deliver_emails

    mail_log = delivery.reload.mail_log
    expect(mail_log.mail_template).to be_nil
    expect(mail_log.from).to eq(VpsAdmin::API::MailTemplates.default_from)
    expect(mail_log.to).to eq('custom@example.test')
    expect(mail_log.subject).to eq('User-created daily report event')
    expect(mail_log.text_plain).to include('Event type: system.daily_report')
  end

  it 'marks released e-mail deliveries sent after SMTP succeeds' do
    delivery, = create_email_delivery!
    stub_mail_delivery!

    task.deliver_emails

    expect(delivery.reload).to be_sent_state
    expect(delivery.event_delivery_attempts.sole).to be_succeeded_state
  end

  it 'marks released e-mail deliveries failed after the last SMTP retry' do
    delivery, = create_email_delivery!
    delivery.update!(attempt_count: VpsAdmin::API::Notifications::MAX_ATTEMPTS - 1)
    stub_mail_delivery!(StandardError.new('smtp rejected'))

    task.deliver_emails

    expect(delivery.reload).to be_failed_state
    expect(delivery.error_summary).to include('StandardError: smtp rejected')
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
    stub_mail_delivery!

    task.deliver_emails

    expect(delivery.reload.mail_log.to).to eq('custom@example.test')
  end

  it 'uses the snapshotted e-mail target when the action is edited later' do
    delivery, action = create_email_delivery!(
      target_kind: :custom,
      target_value: 'old-target@example.test'
    )
    action.update!(target_value: 'new-target@example.test')
    stub_mail_delivery!

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
    end.not_to change(EventDeliveryAttempt, :count)

    expect(delivery.reload).to be_failed_state
    expect(delivery.error_summary).to include('missing report ids')
    expect(delivery.mail_log).to be_nil
  end

  it 'posts signed webhook payloads and marks deliveries sent' do
    delivery, action, route = create_webhook_delivery!(secret: 'super-secret')
    request = nil
    http = instance_double(Net::HTTP)
    response_headers = {
      'content-type' => ['text/plain'],
      'x-webhook-result' => ['stored']
    }
    response = instance_double(
      Net::HTTPOK,
      code: '202',
      body: 'accepted',
      to_hash: response_headers
    )

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
    expect(request['X-VpsAdmin-Event']).to eq('user.test_notification')
    expect(request['X-VpsAdmin-Delivery']).to eq(delivery.id.to_s)
    expect(request['X-VpsAdmin-Signature-256']).to eq("sha256=#{expected_signature}")
    expect(delivery.reload).to be_sent_state
    expect(delivery.response_status).to eq(202)
    expect(delivery.response_body).to eq('accepted')
    expect(delivery.response_headers).to eq(response_headers)
    expect(delivery.attempt_count).to eq(1)
    attempt = delivery.event_delivery_attempts.sole
    expect(attempt).to be_succeeded_state
    expect(attempt.response_headers).to eq(response_headers)
  end

  it 'bounds stored webhook response headers' do
    delivery, = create_webhook_delivery!
    http = instance_double(Net::HTTP)
    response = instance_double(
      Net::HTTPOK,
      code: '202',
      body: 'accepted',
      to_hash: {
        'x-large-header' => ['a' * 20_000],
        'x-second-large-header' => ['b' * 20_000]
      }
    )

    allow(Resolv).to receive(:getaddresses)
      .with('webhook.example')
      .and_return(['93.184.216.34'])
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(response)

    task.deliver_webhooks

    delivery.reload
    attempt = delivery.event_delivery_attempts.sole

    expect(delivery).to be_sent_state
    expect(JSON.dump(delivery.response_headers).bytesize)
      .to be <= VpsAdmin::API::Notifications::RESPONSE_HEADERS_LIMIT
    expect(delivery.response_headers).to include('x-vpsadmin-truncated')
    expect(delivery.response_headers.fetch('x-large-header').first.bytesize)
      .to eq(VpsAdmin::API::Notifications::RESPONSE_HEADER_VALUE_LIMIT)
    expect(attempt.response_headers).to eq(delivery.response_headers)
  end

  it 'claims webhook deliveries exclusively across stale worker reads' do
    delivery, = create_webhook_delivery!(url: 'https://webhook.example/events')
    stale_delivery = EventDelivery.find(delivery.id)
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new('webhook')

    expect(dispatcher.send(:claim_delivery, delivery)).to be_present
    expect(dispatcher.send(:claim_delivery, stale_delivery)).to be_nil

    expect(delivery.reload).to be_sending_state
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.next_attempt_at).to be > Time.now
  end

  it 'marks stale running attempts failed before reclaiming a delivery' do
    delivery, = create_webhook_delivery!(url: 'https://webhook.example/events')
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new('webhook')
    first_attempt = dispatcher.send(:claim_delivery, delivery)

    delivery.reload.update!(next_attempt_at: Time.now - 60)
    second_attempt = dispatcher.send(:claim_delivery, delivery.reload)

    expect(second_attempt.attempt_number).to eq(2)
    expect(first_attempt.reload).to be_failed_state
    expect(first_attempt.finished_at).to be_present
    expect(first_attempt.error_summary).to eq('delivery attempt timed out')
    expect(delivery.reload.attempt_count).to eq(2)
  end

  it 'posts webhooks to the snapshotted target when the action is edited later' do
    delivery, action = create_webhook_delivery!(url: 'https://webhook.example/events')
    action.update!(target_value: 'https://changed.example/events')
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '204', body: '', to_hash: {})

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
    delivery.update!(state: :released, attempt_count: 1)
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
    expect(delivery.reload).to be_released_state
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
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('private address')
  end
end
