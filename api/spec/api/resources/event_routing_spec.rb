# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::EventRouting' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    reset_routing!(SpecSeed.user)
    reset_routing!(SpecSeed.other_user)
  end

  def reset_routing!(user, mailer_enabled: true)
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
    user.update!(mailer_enabled:)
  end

  def receiver_index_path
    vpath('/notification_receivers')
  end

  def receiver_path(id)
    vpath("/notification_receivers/#{id}")
  end

  def receiver_action_index_path(receiver_id)
    vpath("/notification_receivers/#{receiver_id}/action")
  end

  def route_index_path
    vpath('/event_routes')
  end

  def route_path(id)
    vpath("/event_routes/#{id}")
  end

  def matcher_index_path(route_id)
    vpath("/event_routes/#{route_id}/matcher")
  end

  def matcher_path(route_id, id)
    vpath("/event_routes/#{route_id}/matcher/#{id}")
  end

  def event_index_path
    vpath('/events')
  end

  def event_delivery_index_path
    vpath('/event_deliveries')
  end

  def event_path(id)
    vpath("/events/#{id}")
  end

  def event_test_path
    vpath('/events/test')
  end

  def event_types_path
    vpath('/event_types')
  end

  def delivery_index_path(event_id)
    vpath("/events/#{event_id}/deliveries")
  end

  def delivery_path(event_id, delivery_id)
    vpath("/events/#{event_id}/deliveries/#{delivery_id}")
  end

  def delivery_retry_path(event_id, delivery_id)
    vpath("/events/#{event_id}/deliveries/#{delivery_id}/retry")
  end

  def delivery_attempt_index_path(event_id, delivery_id)
    vpath("/events/#{event_id}/deliveries/#{delivery_id}/attempts")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def expect_status(code)
    expect(last_response.status).to eq(code),
                                    "body=#{last_response.body}"
  end

  def receiver_obj
    json.dig('response', 'notification_receiver') || json['response']
  end

  def route_obj
    json.dig('response', 'event_route') || json['response']
  end

  def action_obj
    json.dig('response', 'action') || json.dig('response', 'notification_receiver_action') || json['response']
  end

  def event_obj
    json.dig('response', 'event') || json['response']
  end

  def delivery_obj
    json.dig('response', 'delivery') || json.dig('response', 'event_delivery') || json['response']
  end

  def events
    json.dig('response', 'events') || []
  end

  def deliveries
    json.dig('response', 'deliveries') || json.dig('response', 'event_deliveries') || []
  end

  def attempts
    json.dig('response', 'attempts') || json.dig('response', 'event_delivery_attempts') || []
  end

  def event_types
    json.dig('response', 'event_types') || json.dig('response', 'types') || json['response'] || []
  end

  def action_input_params(resource_name, action_name)
    header 'Accept', 'application/json'
    options vpath('/')
    expect(last_response.status).to eq(200)

    data = json
    data = data['response'] if data.is_a?(Hash) && data['response'].is_a?(Hash)

    resources = data['resources'] || {}
    resource = resource_name.to_s.split('.').reduce(nil) do |desc, name|
      scope = desc ? (desc['resources'] || {}) : resources
      scope[name]
    end
    action = resource&.dig('actions', action_name.to_s) || {}
    action.dig('input', 'parameters') || {}
  end

  describe 'API description' do
    it 'includes event routing scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'event#index',
        'event#show',
        'event#test',
        'event_delivery#index',
        'event_type#index',
        'event.delivery#index',
        'event.delivery#retry',
        'event.delivery#show',
        'event.delivery.attempt#index',
        'event.delivery.attempt#show',
        'event_route#index',
        'event_route#show',
        'event_route#create',
        'event_route#update',
        'event_route#delete',
        'event_route.matcher#index',
        'event_route.matcher#show',
        'event_route.matcher#create',
        'event_route.matcher#update',
        'event_route.matcher#delete',
        'notification_receiver#index',
        'notification_receiver#show',
        'notification_receiver#create',
        'notification_receiver#update',
        'notification_receiver#delete',
        'notification_receiver.action#index',
        'notification_receiver.action#show',
        'notification_receiver.action#create',
        'notification_receiver.action#update',
        'notification_receiver.action#delete'
      )
    end

    it 'publishes route matcher and receiver action choices' do
      route_create = action_input_params(:event_route, :create)
      matcher_create = action_input_params('event_route.matcher', :create)
      action_create = action_input_params('notification_receiver.action', :create)
      event_index = action_input_params(:event, :index)

      expect(
        route_create.dig('event_type', 'validators', 'include', 'values')
      ).to eq(VpsAdmin::API::Events.type_labels)
      expect(
        matcher_create.dig('field', 'validators', 'include', 'values')
      ).to include('parameters.codename' => 'Incident report: Report codename')
      expect(
        matcher_create.dig('operator', 'validators', 'include', 'values')
      ).to eq(::EventRouteMatcher.operator_labels)
      expect(
        action_create.dig('action', 'validators', 'include', 'values')
      ).to eq(::NotificationReceiverAction.action_labels)
      expect(
        action_create.dig('target_kind', 'validators', 'include', 'values')
      ).to eq(::NotificationReceiverAction.target_kind_labels)
      expect(event_index).to include(
        'notification_receiver_id',
        'notification_receiver_action_id'
      )
    end
  end

  it 'lets users configure receivers, routes and inspect routed events' do
    as(SpecSeed.user) do
      json_post receiver_index_path, notification_receiver: {
        label: 'Spec receiver'
      }
    end

    expect_status(200)
    receiver = NotificationReceiver.find(receiver_obj['id'])

    as(SpecSeed.user) do
      json_post receiver_action_index_path(receiver.id), action: {
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events',
        secret: 'super-secret'
      }
    end

    expect_status(200)
    receiver_action = NotificationReceiverAction.find(action_obj['id'])
    expect(action_obj['secret_present']).to be(true)
    expect(action_obj).not_to include('template_name')

    as(SpecSeed.user) do
      json_post route_index_path, event_route: {
        notification_receiver_id: receiver.id,
        event_type: 'vps.incident_report',
        continue: true
      }
    end

    expect_status(200)
    route = EventRoute.find(route_obj['id'])
    expect(route).to be_continue

    as(SpecSeed.user) do
      json_post matcher_index_path(route.id), matcher: {
        field: 'parameters.codename',
        operator: '==',
        value: 'Spec-Abuse'
      }
    end

    expect_status(200)
    expect(json['status']).to be(true), last_response.body
    expect(route.event_route_matchers.reload.count).to eq(1)

    event = VpsAdmin::API::Events.emit!(
      'vps.incident_report',
      user: SpecSeed.user,
      subject: 'Spec incident',
      parameters: {
        'codename' => 'Spec-Abuse'
      }
    )

    as(SpecSeed.user) { json_get event_index_path }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to include(event.id)

    as(SpecSeed.user) { json_get event_index_path, matched_event_route_id: route.id }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get event_index_path, notification_receiver_id: receiver.id }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get event_index_path, notification_receiver_action_id: receiver_action.id }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get delivery_index_path(event.id) }

    expect_status(200)
    expect(deliveries.map { |row| row['action'] }).to eq(['webhook'])
    expect(deliveries.first['notification_receiver_id']).to eq(receiver.id)
    expect(deliveries.first['notification_receiver_label']).to eq('Spec receiver')
    expect(deliveries.first['notification_receiver_action_id']).to eq(receiver_action.id)
    expect(deliveries.first['notification_receiver_action_label']).to eq('Spec webhook')
    expect(deliveries.first['notification_receiver_action_display_target']).to eq('https://example.test/events')
    expect(deliveries.first).not_to include('template_name')

    delivery = event.event_deliveries.sole

    as(SpecSeed.user) { json_get delivery_path(event.id, delivery.id) }

    expect_status(200)
    expect(delivery_obj['target_label']).to eq('Spec webhook')
    expect(delivery_obj['notification_receiver_label']).to eq('Spec receiver')
    expect(delivery_obj['notification_receiver_action_label']).to eq('Spec webhook')
    expect(delivery_obj).not_to include('template_name')

    attempt = delivery.event_delivery_attempts.create!(
      action: delivery.action,
      state: :failed,
      attempt_number: 1,
      started_at: Time.now,
      finished_at: Time.now,
      response_status: 500,
      error_summary: 'spec transport failure'
    )

    as(SpecSeed.user) { json_get delivery_attempt_index_path(event.id, delivery.id) }

    expect_status(200)
    expect(attempts.map { |row| row['id'] }).to eq([attempt.id])
    expect(attempts.first['response_status']).to eq(500)
    expect(attempts.first['error_summary']).to eq('spec transport failure')
  end

  it 'lets admins inspect delivery queues and logs' do
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec queue receiver')
    receiver_action = receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec queue e-mail',
      target_kind: :custom,
      target_value: 'queue@example.test'
    )
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'general',
      severity: 'info',
      subject: 'Spec queue event',
      parameters: {}
    )
    common = {
      event:,
      notification_receiver: receiver,
      notification_receiver_action: receiver_action,
      action: :email,
      target_kind: :custom,
      target_value: 'queue@example.test',
      target_label: 'queue@example.test'
    }
    prepared = EventDelivery.create!(common.merge(state: :prepared, template_name: 'spec_queue_template'))
    released_due = EventDelivery.create!(common.merge(state: :released, next_attempt_at: nil))
    released_later = EventDelivery.create!(
      common.merge(state: :released, next_attempt_at: Time.now + 3600)
    )
    sending = EventDelivery.create!(common.merge(state: :sending, next_attempt_at: Time.now - 60))
    sent = EventDelivery.create!(common.merge(state: :sent, released_at: Time.now - 60, last_attempt_at: Time.now - 30))
    failed = EventDelivery.create!(
      common.merge(
        state: :failed,
        released_at: Time.now - 50,
        last_attempt_at: Time.now - 10,
        error_summary: 'spec failure'
      )
    )
    canceled = EventDelivery.create!(common.merge(state: :canceled, error_summary: 'spec canceled'))
    skipped = EventDelivery.create!(common.merge(state: :skipped, error_summary: 'spec skipped'))

    as(SpecSeed.user) { json_get event_delivery_index_path, event_delivery: { state_group: 'queue' } }

    expect(json['status']).to be(false)

    as(SpecSeed.admin) do
      json_get event_delivery_index_path,
               event_delivery: {
                 state_group: 'queue',
                 notification_receiver_id: receiver.id
               }
    end

    expect_status(200)
    expect(deliveries.map { |row| row['id'] }).to eq(
      [sending.id, released_due.id, released_later.id, prepared.id]
    )
    row = deliveries.detect { |delivery| delivery['id'] == prepared.id }
    expect(row).to include(
      'event_id' => event.id,
      'event_type' => 'user.test_notification',
      'event_subject' => 'Spec queue event',
      'event_user_id' => SpecSeed.user.id,
      'event_user_login' => SpecSeed.user.login,
      'notification_receiver_label' => 'Spec queue receiver',
      'notification_receiver_action_label' => 'Spec queue e-mail',
      'template_name' => 'spec_queue_template'
    )

    as(SpecSeed.admin) do
      json_get event_delivery_index_path,
               event_delivery: {
                 state_group: 'queue',
                 state: 'released',
                 notification_receiver_id: receiver.id
               }
    end

    expect_status(200)
    expect(deliveries.map { |row| row['id'] }).to eq([released_due.id, released_later.id])

    as(SpecSeed.admin) do
      json_get event_delivery_index_path,
               event_delivery: {
                 state_group: 'log',
                 notification_receiver_id: receiver.id
               }
    end

    expect_status(200)
    expect(deliveries.map { |row| row['id'] }).to contain_exactly(sent.id, failed.id, canceled.id, skipped.id)
    expect(deliveries.map { |row| row['id'] }).not_to include(prepared.id, released_due.id, sending.id)
  end

  it 'clears hidden migrated templates when route matching is edited' do
    receiver = NotificationReceiver.create!(
      user: SpecSeed.user,
      label: 'Spec receiver'
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      label: 'Migrated route',
      event_type: 'vps.incident_report',
      email_template_name: 'vps_incident_report'
    )

    as(SpecSeed.user) do
      json_put route_path(route.id), event_route: {
        label: 'Renamed route'
      }
    end

    expect_status(200)
    expect(route.reload.email_template_name).to eq('vps_incident_report')

    as(SpecSeed.user) do
      json_put route_path(route.id), event_route: {
        event_type: 'vps.oom_report'
      }
    end

    expect_status(200)
    expect(route.reload.email_template_name).to be_nil

    route.update!(email_template_name: 'vps_oom_report')

    as(SpecSeed.user) do
      json_post matcher_index_path(route.id), matcher: {
        field: 'parameters.cgroup',
        operator: '==',
        value: '/system.slice/spec.service'
      }
    end

    expect_status(200)
    expect(route.reload.email_template_name).to be_nil

    matcher = route.event_route_matchers.sole
    route.update!(email_template_name: 'vps_oom_report')

    as(SpecSeed.user) do
      json_put matcher_path(route.id, matcher.id), matcher: {
        value: '/system.slice/other.service'
      }
    end

    expect_status(200)
    expect(route.reload.email_template_name).to be_nil

    route.update!(email_template_name: 'vps_oom_report')

    as(SpecSeed.user) { json_delete matcher_path(route.id, matcher.id) }

    expect_status(200)
    expect(route.reload.email_template_name).to be_nil
  end

  it 'lets users retry failed deliveries' do
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'test',
      severity: 'info',
      subject: 'Retryable delivery',
      parameters: {}
    )
    delivery = EventDelivery.create!(
      event:,
      action: :webhook,
      target_kind: :custom,
      target_value: 'https://example.test/retry',
      target_label: 'Retry webhook',
      state: :failed,
      attempt_count: 1,
      error_summary: 'temporary failure'
    )
    publisher = instance_double(VpsAdmin::API::Notifications::Publisher, publish_after_commit: nil)
    allow(VpsAdmin::API::Notifications::Publisher).to receive(:default).and_return(publisher)

    as(SpecSeed.user) { json_post delivery_retry_path(event.id, delivery.id), {} }

    expect_status(200)
    expect(json['status']).to be(true), last_response.body
    expect(delivery.reload).to be_released_state
    expect(delivery.next_attempt_at).to be <= Time.now
    expect(delivery.error_summary).to be_nil
    expect(publisher).to have_received(:publish_after_commit).with([delivery])
  end

  it 'rejects manual retry for non-failed deliveries' do
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'test',
      severity: 'info',
      subject: 'Sent delivery',
      parameters: {}
    )
    delivery = EventDelivery.create!(
      event:,
      action: :webhook,
      target_kind: :custom,
      target_value: 'https://example.test/sent',
      state: :sent,
      attempt_count: 1
    )

    as(SpecSeed.user) { json_post delivery_retry_path(event.id, delivery.id), {} }

    expect(json['status']).to be(false)
    expect(delivery.reload).to be_sent_state
  end

  it 'places new root routes before the generated default catch-all' do
    NotificationReceiver.ensure_defaults_for!(SpecSeed.user)
    default_route = EventRoute.default_route_for(SpecSeed.user)

    as(SpecSeed.user) do
      json_post receiver_index_path, notification_receiver: {
        label: 'Spec receiver'
      }
    end

    expect_status(200)
    receiver = NotificationReceiver.find(receiver_obj['id'])

    as(SpecSeed.user) do
      json_post receiver_action_index_path(receiver.id), action: {
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      }
    end

    expect_status(200)

    as(SpecSeed.user) do
      json_post route_index_path, event_route: {
        notification_receiver_id: receiver.id,
        event_type: 'user.test_notification'
      }
    end

    expect_status(200)
    route = EventRoute.find(route_obj['id'])
    expect(route.position).to be < default_route.reload.position

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec test event'
    )

    expect(event.reload.matched_event_route).to eq(route)
    expect(event.event_deliveries.sole.action).to eq('webhook')
  end

  it 'does not count expired routes toward the route limit' do
    EventRoute::MAX_ROUTES.times do |i|
      EventRoute.create!(
        user: SpecSeed.user,
        label: "Expired route #{i}",
        position: i,
        event_type: 'user.test_notification',
        expires_at: 1.minute.ago
      )
    end

    as(SpecSeed.user) do
      json_post route_index_path, event_route: {
        label: 'Active route',
        event_type: 'user.test_notification'
      }
    end

    expect_status(200)
    expect(route_obj['label']).to eq('Active route')
  end

  it 'limits receiver and action fan-out' do
    NotificationReceiver::MAX_RECEIVERS_PER_USER.times do |i|
      NotificationReceiver.create!(
        user: SpecSeed.user,
        label: "Receiver #{i}"
      )
    end

    as(SpecSeed.user) do
      json_post receiver_index_path, notification_receiver: {
        label: 'Too many receivers'
      }
    end

    expect(json['status']).to be(false)

    reset_routing!(SpecSeed.user)
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')

    NotificationReceiverAction::MAX_ACTIONS_PER_RECEIVER.times do |i|
      receiver.notification_receiver_actions.create!(
        action: :email,
        label: "E-mail #{i}",
        target_kind: :default_recipient
      )
    end

    as(SpecSeed.user) do
      json_post receiver_action_index_path(receiver.id), action: {
        action: 'webhook',
        label: 'Too many actions',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      }
    end

    expect(json['status']).to be(false)
  end

  it 'lists event types and fields' do
    as(SpecSeed.user) { json_get event_types_path }

    expect_status(200)
    incident = event_types.detect { |row| row['name'] == 'vps.incident_report' }
    expect(incident).to be_present
    expect(incident['default_routed']).to be(true)
    expect(incident['fields']).to include('parameters.codename' => 'Incident report: Report codename')
    test = event_types.detect { |row| row['name'] == 'user.test_notification' }
    expect(test['default_routed']).to be(true)
    oom = event_types.detect { |row| row['name'] == 'vps.oom_report' }
    expect(oom['fields']).to include('parameters.stage' => 'OOM report: OOM event stage')
    chain = event_types.detect { |row| row['name'] == 'transaction_chain.state_changed' }
    expect(chain['default_routed']).to be(false)
    expect(chain['fields']).to include('parameters.terminal' => 'Transaction chain state changed: Whether the chain reached a terminal state')
    dns = event_types.detect { |row| row['name'] == 'dns.zone_transfer.failed' }
    expect(dns['default_routed']).to be(false)
  end

  it 'lists monitoring event types and fields when the plugin is enabled', requires_plugins: :monitoring do
    as(SpecSeed.user) { json_get event_types_path }

    expect_status(200)
    monitoring = event_types.detect { |row| row['name'] == 'monitoring.monitor_state_changed' }
    expect(monitoring['default_routed']).to be(true)
    expect(monitoring['fields']).to include(
      'parameters.monitor_name' => 'Monitoring state changed: Monitor internal name',
      'parameters.state' => 'Monitoring state changed: Monitored event state'
    )
  end

  it 'does not register monitoring event types in core-only mode', without_plugins: :monitoring do
    expect(VpsAdmin::API::Events.type_for('monitoring.monitor_state_changed')).to be_nil
    expect(VpsAdmin::API::Events.type_for('monitoring.alert')).to be_nil
  end

  it 'creates test events for the current user' do
    as(SpecSeed.user) do
      json_post event_test_path, event: {
        event_type: 'user.test_notification',
        subject: 'Spec test event',
        parameters_json: JSON.dump(note: 'from spec')
      }
    end

    expect_status(200)
    expect(event_obj['event_type']).to eq('user.test_notification')
    expect(event_obj['subject']).to eq('Spec test event')

    event = Event.find(event_obj['id'])
    expect(event.user).to eq(SpecSeed.user)
    expect(event.parameters).to eq('note' => 'from spec')
    expect(event.source_class).to eq(VpsAdmin::API::Resources::Event::Test::TEST_EVENT_SOURCE_CLASS)
    expect(event.event_deliveries.map(&:action)).to eq(['email'])
  end

  it 'rate-limits test events' do
    VpsAdmin::API::Resources::Event::Test::TEST_EVENT_LIMIT.times do |i|
      Event.create!(
        user: SpecSeed.user,
        event_type: 'user.test_notification',
        category: 'test',
        severity: 'info',
        subject: "Existing test event #{i}",
        parameters: {},
        source_class: VpsAdmin::API::Resources::Event::Test::TEST_EVENT_SOURCE_CLASS
      )
    end

    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          event_type: 'user.test_notification',
          subject: 'Rate-limited test event'
        }
      end
    end.not_to change(Event, :count)

    expect(json['status']).to be(false)
  end

  it 'exposes action-specific delivery details' do
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec detail receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec detail e-mail',
      target_kind: :default_recipient
    )
    receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec detail webhook',
      target_kind: :custom,
      target_value: 'https://example.test/detail'
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec delivery detail event',
      summary: 'Spec delivery detail summary',
      parameters: { note: 'delivery detail' }
    )
    email_delivery = event.event_deliveries.email_action.sole
    webhook_delivery = event.event_deliveries.webhook_action.sole
    email_delivery.update!(template_name: 'spec_internal_template')
    webhook_delivery.update!(
      response_status: 202,
      response_body: 'accepted',
      response_headers: { 'x-spec-detail' => ['delivery'] }
    )
    attempt = webhook_delivery.event_delivery_attempts.create!(
      action: webhook_delivery.action,
      state: :succeeded,
      attempt_number: 1,
      started_at: Time.now,
      finished_at: Time.now,
      response_status: 202,
      response_body: 'accepted',
      response_headers: { 'x-spec-attempt' => ['attempt'] }
    )

    as(SpecSeed.user) { json_get delivery_path(event.id, email_delivery.id) }

    expect_status(200)
    expect(delivery_obj['mail_to']).to eq(SpecSeed.user.email)
    expect(delivery_obj).not_to include('mail_bcc')
    expect(delivery_obj).to include('mail_return_path', 'mail_message_id')
    expect(delivery_obj['mail_subject']).to eq('Spec delivery detail event')
    expect(delivery_obj['mail_text_plain']).to include('Spec delivery detail summary')
    expect(delivery_obj['payload']).to be_nil
    expect(delivery_obj).not_to include('template_name')

    as(SpecSeed.admin) { json_get delivery_path(event.id, email_delivery.id) }

    expect_status(200)
    expect(delivery_obj['template_name']).to eq('spec_internal_template')

    as(SpecSeed.user) { json_get delivery_path(event.id, webhook_delivery.id) }

    expect_status(200)
    expect(JSON.parse(delivery_obj['payload']).dig('event', 'id')).to eq(event.id)
    expect(JSON.parse(delivery_obj['response_headers_json'])).to eq(
      'x-spec-detail' => ['delivery']
    )
    expect(delivery_obj['response_body']).to eq('accepted')

    as(SpecSeed.user) { json_get delivery_attempt_index_path(event.id, webhook_delivery.id) }

    expect_status(200)
    expect(attempts.map { |row| row['id'] }).to eq([attempt.id])
    expect(JSON.parse(attempts.first['response_headers_json'])).to eq(
      'x-spec-attempt' => ['attempt']
    )
  end

  it 'does not expose delivery details across users' do
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec private receiver')
    receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Spec private e-mail',
      target_kind: :default_recipient
    )
    EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec private delivery detail',
      summary: 'Private delivery detail summary'
    )
    delivery = event.event_deliveries.sole
    attempt = delivery.event_delivery_attempts.create!(
      action: delivery.action,
      state: :succeeded,
      attempt_number: 1
    )

    as(SpecSeed.other_user) { json_get delivery_path(event.id, delivery.id) }
    expect_status(404)

    as(SpecSeed.other_user) { json_get delivery_attempt_index_path(event.id, delivery.id) }
    expect_status(200)
    expect(attempts).to eq([])

    as(SpecSeed.other_user) do
      json_get vpath("/events/#{event.id}/deliveries/#{delivery.id}/attempts/#{attempt.id}")
    end
    expect_status(404)
  end

  it 'does not let users create test events for another user' do
    as(SpecSeed.user) do
      json_post event_test_path, event: {
        user: SpecSeed.other_user.id,
        subject: 'nope'
      }
    end

    expect(json['status']).to be(false)
    expect(Event.where(subject: 'nope')).to be_empty
  end

  it 'does not rehydrate other users objects from test-event parameters' do
    other_attempt = create_failed_login!(user: SpecSeed.other_user)
    other_totp = UserTotpDevice.create!(
      user: SpecSeed.other_user,
      label: 'Other TOTP',
      secret: ROTP::Base32.random_base32,
      recovery_code: 'recovery',
      confirmed: true,
      enabled: true
    )

    as(SpecSeed.user) do
      json_post event_test_path, event: {
        event_type: 'user.failed_logins',
        subject: 'foreign failed login ids',
        parameters_json: JSON.dump(attempt_group_ids: [[other_attempt.id]])
      }
    end

    expect_status(200)
    failed_logins_event = Event.find(event_obj['id'])
    expect(VpsAdmin::API::Events.email_vars_for(failed_logins_event).fetch(:attempt_groups)).to eq([[]])

    as(SpecSeed.user) do
      json_post event_test_path, event: {
        event_type: 'user.totp_recovery_code_used',
        subject: 'foreign totp id',
        parameters_json: JSON.dump(totp_device_id: other_totp.id)
      }
    end

    expect_status(200)
    totp_event = Event.find(event_obj['id'])
    expect(VpsAdmin::API::Events.email_vars_for(totp_event).fetch(:totp_device)).to be_nil
  end

  it 'rejects oversized test-event parameters' do
    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          subject: 'oversized parameters',
          parameters_json: JSON.dump(note: 'x' * ::Event::MAX_PARAMETERS_JSON_SIZE)
        }
      end
    end.not_to change(Event, :count)

    expect(json['status']).to be(false)
  end

  it 'rejects non-object test-event parameters' do
    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          subject: 'array parameters',
          parameters_json: JSON.dump(['nope'])
        }
      end
    end.not_to change(Event, :count)

    expect(json['status']).to be(false)
  end

  it 'rejects oversized test-event summaries' do
    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          subject: 'oversized summary',
          summary: 'x' * (::Event::MAX_SUMMARY_LENGTH + 1)
        }
      end
    end.not_to change(Event, :count)

    expect(json['status']).to be(false)
  end

  it 'restricts users to their own receivers, routes and events' do
    other_receiver = NotificationReceiver.create!(
      user: SpecSeed.other_user,
      label: 'Other receiver'
    )
    other_receiver_action = other_receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Other webhook',
      target_kind: :custom,
      target_value: 'https://example.test/other'
    )
    other_route = EventRoute.create!(
      user: SpecSeed.other_user,
      notification_receiver: other_receiver,
      event_type: 'vps.incident_report'
    )
    other_event = VpsAdmin::API::Events.emit!(
      'vps.incident_report',
      user: SpecSeed.other_user,
      subject: 'Other incident'
    )

    as(SpecSeed.user) { json_get receiver_path(other_receiver.id) }
    expect(json['status']).to be(false)

    as(SpecSeed.user) { json_put route_path(other_route.id), event_route: { label: 'nope' } }
    expect(json['status']).to be(false)
    expect(other_route.reload.label).to be_nil

    as(SpecSeed.user) { json_get event_path(other_event.id) }
    expect(json['status']).to be(false)

    as(SpecSeed.user) { json_delete receiver_path(other_receiver.id) }
    expect(json['status']).to be(false)
    expect(NotificationReceiver.exists?(other_receiver.id)).to be(true)
    expect(NotificationReceiverAction.exists?(other_receiver_action.id)).to be(true)
  end
end
