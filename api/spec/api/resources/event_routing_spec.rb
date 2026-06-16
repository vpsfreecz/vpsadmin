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

  def receiver_action_pairing_path(receiver_id, action_id)
    vpath("/notification_receivers/#{receiver_id}/action/#{action_id}/create_pairing_token")
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

  def event_index_path
    vpath('/events')
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
        'event_type#index',
        'event.delivery#index',
        'event.delivery#show',
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
        'notification_receiver.action#delete',
        'notification_receiver.action#create_pairing_token'
      )
    end

    it 'publishes route matcher and receiver action choices' do
      route_create = action_input_params(:event_route, :create)
      matcher_create = action_input_params('event_route.matcher', :create)
      action_create = action_input_params('notification_receiver.action', :create)

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

    as(SpecSeed.user) { json_get delivery_index_path(event.id) }

    expect_status(200)
    expect(deliveries.map { |row| row['action'] }).to eq(['webhook'])
    expect(deliveries.first['notification_receiver_id']).to eq(receiver.id)
    expect(deliveries.first['notification_receiver_action_id']).to eq(receiver_action.id)

    delivery = event.event_deliveries.sole

    as(SpecSeed.user) { json_get delivery_path(event.id, delivery.id) }

    expect_status(200)
    expect(delivery_obj['target_label']).to eq('Spec webhook')
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

  it 'creates Telegram pairing tokens' do
    as(SpecSeed.user) do
      json_post receiver_index_path, notification_receiver: {
        label: 'Spec receiver'
      }
    end

    expect_status(200)
    receiver = NotificationReceiver.find(receiver_obj['id'])

    as(SpecSeed.user) do
      json_post receiver_action_index_path(receiver.id), action: {
        action: 'telegram',
        label: 'Spec Telegram'
      }
    end

    expect_status(200)
    original_token = action_obj['verification_token']
    expect(original_token).to be_present
    expect(action_obj['target_kind']).to eq('custom')
    expect(action_obj['target_value']).to be_nil

    action = NotificationReceiverAction.find(action_obj['id'])

    as(SpecSeed.user) { json_post receiver_action_pairing_path(receiver.id, action.id), {} }

    expect_status(200)
    expect(action_obj['verification_token']).to be_present
    expect(action_obj['verification_token']).not_to eq(original_token)
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
    expect(incident['fields']).to include('parameters.codename' => 'Incident report: Report codename')
    oom = event_types.detect { |row| row['name'] == 'vps.oom_report' }
    expect(oom['fields']).to include('parameters.stage' => 'OOM report: OOM event stage')
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
