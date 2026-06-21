# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

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

  def create_webhook_delivery!(url: 'https://webhook.example/events', secret: nil, user: SpecSeed.user)
    receiver = NotificationReceiver.create!(user:, label: 'Spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec webhook',
      target_kind: :custom,
      target_value: url,
      secret:
    )
    route = EventRoute.create!(
      user:,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )
    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user:,
      subject: 'Spec event',
      parameters: { note: 'from task spec' }
    )

    [event.event_deliveries.sole, action, route]
  end

  def create_telegram_delivery!(target_value: '123456789',
                                summary: 'Spec Telegram summary',
                                parameters: { note: 'from Telegram task spec' })
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec Telegram receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :telegram,
      label: 'Spec Telegram',
      target_kind: :custom,
      target_value:,
      verified_at: Time.now
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )
    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec Telegram event',
      summary:,
      parameters:
    )

    [event.event_deliveries.sole, action, route]
  end

  def stub_telegram_response(code: '200', body: { ok: true, result: { message_id: 42 } })
    request = nil
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code:, body: JSON.dump(body))

    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('api.telegram.org')
      expect(port).to eq(443)
      expect(options).to include(
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

    -> { request }
  end

  def create_managed_private_ip!(user: nil)
    network = create_private_network!(purpose: :any)
    create_ipv4_address_in_network!(
      network:,
      location: SpecSeed.location,
      user:
    )
  end

  def create_managed_public_ip!(user: nil)
    network = create_private_network!(
      address: '8.18.0.0',
      role: :public_access,
      purpose: :any
    )
    create_ipv4_address_in_network!(
      network:,
      location: SpecSeed.location,
      user:
    )
  end

  def create_public_network!(address:, prefix:, split_prefix:)
    create_private_network!(
      address:,
      prefix:,
      split_prefix:,
      role: :public_access,
      purpose: :any
    )
  end

  def create_public_subnet_ip!(network:, addr:, user:)
    create_ip_address!(
      network:,
      location: SpecSeed.location,
      addr:,
      prefix: network.split_prefix,
      size: 2**(32 - network.split_prefix),
      user:
    )
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

  def create_manual_webhook_delivery!(event:, url: 'https://webhook.example/events')
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Manual spec receiver')
    action = receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Manual spec webhook',
      target_kind: :custom,
      target_value: url
    )

    EventDelivery.create!(
      event:,
      action: :webhook,
      target_kind: :custom,
      target_value: url,
      target_label: action.label,
      notification_receiver: receiver,
      notification_receiver_action: action,
      state: :released,
      next_attempt_at: Time.now
    )
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

  it 'defaults dispatcher concurrency and e-mail throttles' do
    email = VpsAdmin::API::Notifications::Dispatcher.new('email')
    telegram = VpsAdmin::API::Notifications::Dispatcher.new('telegram')
    webhook = VpsAdmin::API::Notifications::Dispatcher.new('webhook')

    expect(email.send(:concurrency)).to eq(2)
    expect(email.send(:email_worker_delay)).to eq(1.0)
    expect(email.send(:email_domain_min_delivery_interval)).to eq(1.0)
    expect(telegram.send(:concurrency)).to eq(2)
    expect(webhook.send(:concurrency)).to eq(4)
  end

  it 'runs queued deliveries with configured worker concurrency' do
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: { 'webhook' => { 'concurrency' => 2 } }
    )
    mutex = Mutex.new
    condition = ConditionVariable.new
    started = []
    release = false

    dispatcher.define_singleton_method(:dispatch_delivery_id) do |id, **kwargs|
      worker_state = kwargs.fetch(:worker_state)

      mutex.synchronize do
        started << [id, worker_state.fetch(:index)]
        condition.broadcast
        condition.wait(mutex) until release
      end
    end

    expect(dispatcher.send(:submit_delivery_id, 1)).to be(true)
    expect(dispatcher.send(:submit_delivery_id, 2)).to be(true)

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until started.size == 2
      end
    end

    expect(started.map(&:first)).to contain_exactly(1, 2)
    expect(started.map(&:last).uniq.size).to eq(2)
  ensure
    mutex.synchronize do
      release = true
      condition.broadcast
    end
    dispatcher&.send(:wait_for_idle)
    dispatcher&.send(:stop_workers)
  end

  it 'does not queue the same delivery id while it is running' do
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: { 'webhook' => { 'concurrency' => 2 } }
    )
    mutex = Mutex.new
    condition = ConditionVariable.new
    started = []
    release = false

    dispatcher.define_singleton_method(:dispatch_delivery_id) do |id, **_kwargs|
      mutex.synchronize do
        started << id
        condition.broadcast
        condition.wait(mutex) until release
      end
    end

    expect(dispatcher.send(:submit_delivery_id, 42)).to be(true)

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until started.size == 1
      end
    end

    expect(dispatcher.send(:submit_delivery_id, 42)).to be(false)
    expect(started).to eq([42])
  ensure
    mutex.synchronize do
      release = true
      condition.broadcast
    end
    dispatcher&.send(:wait_for_idle)
    dispatcher&.send(:stop_workers)
  end

  it 'does not treat successful worker results as throttle delays' do
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: { 'webhook' => { 'concurrency' => 1 } }
    )
    mutex = Mutex.new
    condition = ConditionVariable.new
    processed = []

    dispatcher.define_singleton_method(:dispatch_delivery_id) do |id, **_kwargs|
      mutex.synchronize do
        processed << id
        condition.broadcast
      end

      true
    end

    expect(dispatcher.send(:submit_delivery_id, 1)).to be(true)

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until processed == [1]
      end
    end
    Timeout.timeout(2) { dispatcher.send(:wait_for_idle) }

    expect(dispatcher.send(:submit_delivery_id, 2)).to be(true)

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until processed == [1, 2]
      end
    end
    Timeout.timeout(2) { dispatcher.send(:wait_for_idle) }
  ensure
    dispatcher&.send(:stop_workers)
  end

  it 'does not reserve more queued deliveries than the dispatcher limit' do
    previous_limit = ENV.fetch('LIMIT', nil)
    ENV['LIMIT'] = '2'
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: { 'webhook' => { 'concurrency' => 1 } }
    )
    mutex = Mutex.new
    condition = ConditionVariable.new
    started = []
    release = false

    dispatcher.define_singleton_method(:dispatch_delivery_id) do |id, **_kwargs|
      mutex.synchronize do
        started << id
        condition.broadcast
        condition.wait(mutex) until release
      end
    end

    expect(dispatcher.send(:submit_delivery_id, 1)).to be(true)
    expect(dispatcher.send(:submit_delivery_id, 2)).to be(true)

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until started == [1]
      end
    end

    expect(dispatcher.send(:submit_delivery_id, 3)).to be(false)
  ensure
    ENV['LIMIT'] = previous_limit
    if mutex && condition
      mutex.synchronize do
        release = true
        condition.broadcast
      end
    end
    dispatcher&.send(:wait_for_idle)
    dispatcher&.send(:stop_workers)
  end

  it 'scans past one e-mail domain when selecting due deliveries' do
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'email',
      config: {
        'email' => {
          'concurrency' => 3,
          'worker_delay' => 0,
          'domain_min_delivery_interval' => 10
        }
      }
    )
    deliveries = [
      create_due_email_delivery!('first@gmail.com'),
      create_due_email_delivery!('second@gmail.com'),
      create_due_email_delivery!('third@gmail.com'),
      create_due_email_delivery!('other@fastmail.com')
    ]
    selected_ids = dispatcher.send(:due_deliveries, 3).map(&:id)

    expect(selected_ids).to include(deliveries.first.id, deliveries.last.id)
    expect(selected_ids).not_to include(deliveries.third.id)
  end

  it 'prefers a sendable e-mail domain when only one delivery slot is open' do
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'email',
      config: {
        'email' => {
          'concurrency' => 1,
          'worker_delay' => 0,
          'domain_min_delivery_interval' => 10
        }
      }
    )
    throttled = create_due_email_delivery!('first@gmail.com')
    sendable = create_due_email_delivery!('other@fastmail.com')

    expect(dispatcher.send(:email_domain_limiter).reserve_or_delay(['gmail.com'])).to eq(0)

    selected_ids = dispatcher.send(:due_deliveries, 1, scan_limit: 2).map(&:id)

    expect(selected_ids).to eq([sendable.id])
    expect(selected_ids).not_to include(throttled.id)
  end

  it 'does not let one throttled e-mail domain occupy all workers' do
    mutex = nil
    condition = nil
    release_first = false
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'email',
      config: {
        'email' => {
          'concurrency' => 3,
          'worker_delay' => 0,
          'domain_min_delivery_interval' => 10
        }
      }
    )
    mutex = Mutex.new
    condition = ConditionVariable.new
    deliveries = {
      1 => fake_email_delivery(1, 'first@gmail.com'),
      2 => fake_email_delivery(2, 'second@gmail.com'),
      3 => fake_email_delivery(3, 'third@gmail.com'),
      4 => fake_email_delivery(4, 'other@fastmail.com')
    }
    started = []

    dispatcher.define_singleton_method(:find_delivery) { |id| deliveries.fetch(id) }
    dispatcher.define_singleton_method(:claim_delivery) { |_delivery| Object.new }
    dispatcher.define_singleton_method(:mark_success!) { |_delivery, _attempt, _result| nil }
    dispatcher.define_singleton_method(:deliver) do |delivery|
      mutex.synchronize do
        started << delivery.id
        condition.broadcast
        condition.wait(mutex) if delivery.id == 1 && !release_first
      end

      {}
    end

    [1, 2, 3, 4].each do |id|
      expect(dispatcher.send(:submit_delivery_id, id)).to be(true)
    end

    Timeout.timeout(2) do
      mutex.synchronize do
        condition.wait(mutex) until started.include?(1) && started.include?(4)
      end
    end

    expect(started).to include(4)
    expect(started).not_to include(2, 3)
  ensure
    if mutex && condition
      mutex.synchronize do
        release_first = true
        condition.broadcast
      end
    end
    dispatcher&.send(:stop_workers)
  end

  it 'spaces repeated e-mail starts made by one worker' do
    now = 100.0
    sleeps = []
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'email',
      config: {
        'email' => {
          'worker_delay' => 1,
          'domain_min_delivery_interval' => 0
        }
      },
      monotonic_clock: -> { now },
      sleeper: lambda { |seconds|
        sleeps << seconds
        now += seconds
      }
    )
    delivery, = create_email_delivery!
    worker_state = {}

    dispatcher.send(:wait_for_email_throttles!, delivery, worker_state)
    dispatcher.send(:wait_for_email_throttles!, delivery, worker_state)

    expect(sleeps).to eq([1.0])
  end

  it 'throttles repeated e-mail recipient domains' do
    now = 200.0
    sleeps = []
    limiter = VpsAdmin::API::Notifications::DomainRateLimiter.new(
      interval: 1.0,
      clock: -> { now },
      sleeper: lambda { |seconds|
        sleeps << seconds
        now += seconds
      }
    )

    limiter.wait(%w[gmail.com example.net])
    limiter.wait(['example.net'])
    limiter.wait(['fastmail.com'])

    expect(sleeps).to eq([1.0])
  end

  it 'extracts e-mail throttle domains from to, cc, and bcc recipients' do
    delivery, = create_email_delivery!
    delivery.mail_log.update!(
      to: 'User <user@gmail.com>',
      cc: 'Copy <copy@example.net>',
      bcc: 'Hidden <hidden@GMAIL.COM>'
    )
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new('email')

    expect(dispatcher.send(:email_recipient_domains, delivery))
      .to contain_exactly('gmail.com', 'example.net')
  end

  def fake_email_delivery(id, recipient)
    mail_log = Struct.new(:to, :cc, :bcc).new(recipient, '', '')
    delivery = Struct.new(:id, :action, :mail_log).new(id, 'email', mail_log)
    delivery.define_singleton_method(:reload) { self }
    delivery
  end

  def create_due_email_delivery!(recipient)
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'test',
      severity: 'info',
      subject: 'Spec due e-mail',
      parameters: {}
    )
    mail_log = MailLog.create!(
      user: SpecSeed.user,
      to: recipient,
      cc: '',
      bcc: '',
      from: 'noreply@example.test',
      subject: 'Spec due e-mail',
      text_plain: 'Spec due e-mail body'
    )

    EventDelivery.create!(
      event:,
      mail_log:,
      action: :email,
      target_kind: :default_recipient,
      target_label: 'Default recipient',
      state: :released,
      next_attempt_at: Time.now
    )
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
    delivery = create_direct_custom_email_delivery!
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

  it 'sends Telegram messages and marks deliveries sent' do
    delivery, action, route = create_telegram_delivery!
    request = stub_telegram_response

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    body = JSON.parse(request.call.body)

    expect(body['chat_id']).to eq('123456789')
    expect(body['text']).to include('Spec Telegram event')
    expect(body['text']).to include('Event: user.test_notification')
    expect(request.call.path).to eq('/bot123:telegram-token/sendMessage')
    expect(delivery.reload).to be_sent_state
    expect(delivery.notification_receiver_action).to eq(action)
    expect(delivery.event_route).to eq(route)
    expect(delivery.response_status).to eq(200)
    expect(delivery.provider_message_id).to eq('42')
    expect(delivery.attempt_count).to eq(1)
    attempt = delivery.event_delivery_attempts.sole
    expect(attempt).to be_succeeded_state
    expect(attempt.provider_message_id).to eq('42')
  end

  it 'does not include summaries or parameters in default Telegram messages' do
    delivery, = create_telegram_delivery!(
      summary: 'Sensitive incident body',
      parameters: {
        note: 'from Telegram task spec',
        text: 'Sensitive incident body'
      }
    )
    request = stub_telegram_response

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    text = JSON.parse(request.call.body).fetch('text')

    expect(text).to include('Spec Telegram event')
    expect(text).not_to include('from Telegram task spec')
    expect(text).not_to include('Sensitive incident body')
    expect(text).not_to include('Summary:')
    expect(delivery.reload).to be_sent_state
  end

  it 'sends Telegram messages to the snapshotted chat when the action is re-paired later' do
    delivery, action = create_telegram_delivery!(target_value: '111')
    action.pair_telegram_chat!('222')
    request = stub_telegram_response

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    expect(JSON.parse(request.call.body).fetch('chat_id')).to eq('111')
    expect(delivery.reload).to be_sent_state
  end

  it 'does not retry Telegram deliveries for muted receivers' do
    delivery, = create_telegram_delivery!
    delivery.update!(state: :released, attempt_count: 1)
    delivery.notification_receiver.update!(mute: true)

    allow(Net::HTTP).to receive(:start)

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_canceled_state
    expect(delivery.error_summary).to include('receiver')
  end

  it 'does not send Telegram deliveries for unverified actions' do
    delivery, action = create_telegram_delivery!
    action.update!(verified_at: nil)

    allow(Net::HTTP).to receive(:start)

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_canceled_state
    expect(delivery.error_summary).to include('telegram action is not available')
  end

  it 'retries Telegram deliveries when the bot token is missing' do
    delivery, = create_telegram_delivery!

    allow(Net::HTTP).to receive(:start)

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => nil) do
      task.deliver_telegrams
    end

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.next_attempt_at).to be_present
    expect(delivery.error_summary).to include('Telegram bot token is not configured')
  end

  it 'retries Telegram deliveries when the API returns an error' do
    delivery, = create_telegram_delivery!
    stub_telegram_response(
      code: '429',
      body: {
        ok: false,
        description: 'Too Many Requests'
      }
    )

    with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.deliver_telegrams
    end

    delivery.reload

    expect(delivery).to be_released_state
    expect(delivery.response_status).to eq(429)
    expect(delivery.response_body).to include('Too Many Requests')
    expect(delivery.error_summary).to include('Telegram API: Too Many Requests')
    expect(delivery.attempt_count).to eq(1)
    expect(delivery.next_attempt_at).to be_present
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

  it 'calls untracked private webhook addresses from configured exception ranges' do
    delivery, = create_webhook_delivery!(url: 'http://127.0.0.1:9292/events')
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: {
        'webhook' => {
          'allowed_untracked_private_ranges' => ['127.0.0.0/8']
        }
      }
    )
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '204', body: '', to_hash: {})

    allow(Resolv).to receive(:getaddresses)
      .with('127.0.0.1')
      .and_return(['127.0.0.1'])
    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('127.0.0.1')
      expect(port).to eq(9292)
      expect(options).to include(ipaddr: '127.0.0.1', use_ssl: false)
      block.call(http)
    end
    allow(http).to receive(:request).and_return(response)

    dispatcher.dispatch_due

    expect(delivery.reload).to be_sent_state
    expect(delivery.response_status).to eq(204)
  end

  it 'does not call untracked private webhook addresses outside configured exception ranges' do
    delivery, = create_webhook_delivery!(url: 'http://10.0.0.1/events')
    dispatcher = VpsAdmin::API::Notifications::Dispatcher.new(
      'webhook',
      config: {
        'webhook' => {
          'allowed_untracked_private_ranges' => ['127.0.0.0/8']
        }
      }
    )

    allow(Resolv).to receive(:getaddresses)
      .with('10.0.0.1')
      .and_return(['10.0.0.1'])
    allow(Net::HTTP).to receive(:start)

    dispatcher.dispatch_due

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('private address')
  end

  it 'calls same-user managed private webhook addresses without configured exception ranges' do
    ip_address = create_managed_private_ip!(user: SpecSeed.user)
    delivery, = create_webhook_delivery!(url: "http://#{ip_address.addr}:9292/events")
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '204', body: '', to_hash: {})

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq(ip_address.addr)
      expect(port).to eq(9292)
      expect(options).to include(ipaddr: ip_address.addr, use_ssl: false)
      block.call(http)
    end
    allow(http).to receive(:request).and_return(response)

    task.deliver_webhooks

    expect(delivery.reload).to be_sent_state
    expect(delivery.response_status).to eq(204)
  end

  it 'does not call other-user managed private webhook addresses' do
    ip_address = create_managed_private_ip!(user: SpecSeed.other_user)
    delivery, = create_webhook_delivery!(url: "http://#{ip_address.addr}:9292/events")

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'does not call other-user managed public webhook addresses' do
    ip_address = create_managed_public_ip!(user: SpecSeed.other_user)
    delivery, = create_webhook_delivery!(url: "http://#{ip_address.addr}:9292/events")

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'does not call managed unowned webhook addresses' do
    ip_address = create_managed_private_ip!
    delivery, = create_webhook_delivery!(url: "http://#{ip_address.addr}:9292/events")

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'does not call managed webhook addresses from ownerless events' do
    ip_address = create_managed_private_ip!(user: SpecSeed.user)
    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      subject: 'Ownerless spec event',
      route: false,
      release: false
    )
    delivery = create_manual_webhook_delivery!(
      event:,
      url: "http://#{ip_address.addr}:9292/events"
    )

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'allows managed webhook addresses owned through a VPS network interface' do
    fixture = create_netif_vps_fixture!(user: SpecSeed.user)
    network = create_private_network!(purpose: :any)
    ip_address = create_ipv4_address_in_network!(
      network:,
      location: SpecSeed.location,
      network_interface: fixture.fetch(:netif)
    )
    delivery, = create_webhook_delivery!(url: "http://#{ip_address.addr}:9292/events")
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPOK, code: '204', body: '', to_hash: {})

    allow(Resolv).to receive(:getaddresses)
      .with(ip_address.addr)
      .and_return([ip_address.addr])
    allow(Net::HTTP).to receive(:start) do |host, _port, **options, &block|
      expect(host).to eq(ip_address.addr)
      expect(options).to include(ipaddr: ip_address.addr)
      block.call(http)
    end
    allow(http).to receive(:request).and_return(response)

    task.deliver_webhooks

    expect(delivery.reload).to be_sent_state
  end

  it 'finds managed webhook addresses in later overlapping networks' do
    create_public_network!(
      address: '8.18.0.0',
      prefix: 16,
      split_prefix: 24
    )
    network = create_public_network!(
      address: '8.18.42.0',
      prefix: 24,
      split_prefix: 24
    )
    create_public_subnet_ip!(
      network:,
      addr: '8.18.42.0',
      user: SpecSeed.other_user
    )
    delivery, = create_webhook_delivery!(url: 'http://8.18.42.15/events')

    allow(Resolv).to receive(:getaddresses)
      .with('8.18.42.15')
      .and_return(['8.18.42.15'])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'does not call managed webhook addresses with conflicting overlapping owners' do
    broad_network = create_public_network!(
      address: '8.19.0.0',
      prefix: 16,
      split_prefix: 24
    )
    create_public_subnet_ip!(
      network: broad_network,
      addr: '8.19.42.0',
      user: SpecSeed.user
    )
    narrow_network = create_public_network!(
      address: '8.19.42.0',
      prefix: 24,
      split_prefix: 32
    )
    create_public_subnet_ip!(
      network: narrow_network,
      addr: '8.19.42.15',
      user: SpecSeed.other_user
    )
    delivery, = create_webhook_delivery!(url: 'http://8.19.42.15/events')

    allow(Resolv).to receive(:getaddresses)
      .with('8.19.42.15')
      .and_return(['8.19.42.15'])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
  end

  it 'does not call webhook hosts with any forbidden DNS address' do
    owned_ip = create_managed_private_ip!(user: SpecSeed.user)
    other_ip = create_managed_private_ip!(user: SpecSeed.other_user)
    delivery, = create_webhook_delivery!(url: 'http://webhook.example/events')

    allow(Resolv).to receive(:getaddresses)
      .with('webhook.example')
      .and_return([owned_ip.addr, other_ip.addr])
    allow(Net::HTTP).to receive(:start)

    task.deliver_webhooks

    expect(Net::HTTP).not_to have_received(:start)
    expect(delivery.reload).to be_released_state
    expect(delivery.error_summary).to include('not owned by the event user')
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
