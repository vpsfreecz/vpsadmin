# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::EventRouting' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    reset_routing!(SpecSeed.admin)
    reset_routing!(SpecSeed.user)
    reset_routing!(SpecSeed.other_user)
  end

  def reset_routing!(user)
    EventRouteMatch.delete_all
    EventRoutingContext.where(user_id: user.id).delete_all
    EventRouteMatcher.joins(:event_route).where(event_routes: { user_id: user.id }).delete_all
    NotificationReceiverTarget
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: user.id })
      .delete_all
    NotificationTarget.where(user:).delete_all
    EventRoute.where(user:).delete_all
    NotificationReceiver.where(user:).delete_all
    user.user_notification_delivery_methods.delete_all
  end

  def receiver_index_path
    vpath('/notification_receivers')
  end

  def receiver_path(id)
    vpath("/notification_receivers/#{id}")
  end

  def notification_target_index_path
    vpath('/notification_targets')
  end

  def notification_target_path(id)
    vpath("/notification_targets/#{id}")
  end

  def notification_target_pairing_token_path(id)
    vpath("/notification_targets/#{id}/create_pairing_token")
  end

  def notification_target_email_send_path(id)
    vpath("/notification_targets/#{id}/send_email_verification")
  end

  def notification_target_email_confirm_path(id)
    vpath("/notification_targets/#{id}/confirm_email_verification")
  end

  def receiver_target_index_path(receiver_id)
    vpath("/notification_receivers/#{receiver_id}/target")
  end

  def receiver_target_path(receiver_id, target_id)
    vpath("/notification_receivers/#{receiver_id}/target/#{target_id}")
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

  def route_match_index_path(event_id)
    vpath("/events/#{event_id}/route_matches")
  end

  def route_match_path(event_id, route_match_id)
    vpath("/events/#{event_id}/route_matches/#{route_match_id}")
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

  def sms_notifications_config
    {
      'sms' => {
        'enabled' => true,
        'configured' => true,
        'callback_url' => 'https://api.example.test/internal/notifications/sms/callback',
        'gateways' => [
          {
            'name' => 'brq',
            'url' => 'https://sms-brq.example/v1/sms',
            'token' => 'brq-token'
          }
        ]
      }
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

  def target_obj
    json.dig('response', 'notification_target') || json['response']
  end

  def receiver_target_obj
    json.dig('response', 'target') || json.dig('response', 'notification_receiver_target') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
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

  def route_matches
    json.dig('response', 'route_matches') || json.dig('response', 'event_route_matches') || []
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

  def create_notification_target!(attrs, actor: SpecSeed.user)
    as(actor) do
      json_post notification_target_index_path, notification_target: attrs
    end
    expect_status(200)
    obj = target_obj
    expect(obj).to be_present, last_response.body
    NotificationTarget.find(obj.fetch('id'))
  end

  def link_notification_target!(receiver, target, actor: SpecSeed.user)
    as(actor) do
      json_post receiver_target_index_path(receiver.id), target: {
        notification_target_id: target.id
      }
    end
    expect_status(200)
    NotificationReceiverTarget.find(receiver_target_obj.fetch('id'))
  end

  def create_linked_target!(receiver, attrs, actor: SpecSeed.user)
    target = create_notification_target!(attrs, actor:)
    link = link_notification_target!(receiver, target, actor:)
    [target, link]
  end

  def create_delivery_context!(event, user: event.user)
    EventRoutingContext.create!(
      event:,
      recipient_user: user,
      subject_relation: event.user_id == user.id ? 'self' : 'other_user',
      source: event.user_id == user.id ? 'direct_route' : 'visible_route',
      routing_state: :routed
    )
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
        'notification_target#index',
        'notification_target#show',
        'notification_target#create',
        'notification_target#send_email_verification',
        'notification_target#confirm_email_verification',
        'notification_target#create_pairing_token',
        'notification_target#send_sms_verification_code',
        'notification_target#confirm_sms_verification_code',
        'notification_target#update',
        'notification_target#delete',
        'notification_receiver.target#index',
        'notification_receiver.target#show',
        'notification_receiver.target#create',
        'notification_receiver.target#update',
        'notification_receiver.target#delete'
      )
    end

    it 'publishes route matcher and notification target choices' do
      route_create = action_input_params(:event_route, :create)
      matcher_create = action_input_params('event_route.matcher', :create)
      target_create = action_input_params(:notification_target, :create)
      receiver_target_create = action_input_params('notification_receiver.target', :create)
      receiver_target_update = action_input_params('notification_receiver.target', :update)
      event_index = action_input_params(:event, :index)
      expected_type_labels = VpsAdmin::API::Events.type_labels.except(
        'monitoring.alert_chain',
        'monitoring.spec_alert'
      )

      expect(
        route_create.dig('event_type', 'validators', 'include', 'values')
      ).to eq(expected_type_labels)
      expect(
        route_create.dig('subject_scope', 'validators', 'include', 'values')
      ).to eq(::EventRoute.subject_scope_labels)
      expect(
        matcher_create.dig('field', 'validators', 'include', 'values')
      ).to include(
        'codename' => 'Incident report codename assigned by vpsAdmin',
        'roles' => 'Notification roles declared by the event type',
        'subject_relation' => 'Relationship between route owner and event subject'
      )
      expect(
        matcher_create.dig('operator', 'validators', 'include', 'values')
      ).to eq(::EventRouteMatcher.operator_labels)
      expect(
        target_create.dig('action', 'validators', 'include', 'values')
      ).to eq(::NotificationTarget.action_labels)
      expect(
        target_create.dig('target_kind', 'validators', 'include', 'values')
      ).to eq(::NotificationTarget.target_kind_labels)
      expect(receiver_target_create).to include('notification_target_id')
      expect(receiver_target_create).not_to include('enabled')
      expect(receiver_target_update).to include('position')
      expect(receiver_target_update).not_to include('enabled')
      expect(event_index).to include(
        'event_route_id',
        'notification_receiver_id',
        'notification_target_id',
        'notification_receiver_target_id',
        'subject_relation'
      )
    end

    it 'keeps dedicated system report migration routes matcher-free' do
      migration = File.expand_path(
        '../../../db/migrate/20260624121000_migrate_legacy_email_recipients_to_routes',
        __dir__
      )
      require migration unless defined?(MigrateLegacyEmailRecipientsToRoutes)

      route_map = MigrateLegacyEmailRecipientsToRoutes::TEMPLATE_ROUTE_MAP

      expect(route_map.fetch('daily_report')).not_to have_key(:relation)
      expect(route_map.fetch('payments_overview')).not_to have_key(:relation)
      expect(route_map.fetch('user_create').fetch(:relation)).to eq('other_user')
      expect(route_map.fetch('expiration_user_active').fetch(:relation)).to eq('other_user')
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

    target, receiver_target = create_linked_target!(
      receiver,
      {
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events',
        secret: 'super-secret'
      }
    )
    expect(target.secret_present?).to be(true)

    as(SpecSeed.user) { json_get receiver_target_path(receiver.id, receiver_target.id) }
    expect_status(200)
    expect(receiver_target_obj).not_to include('enabled')
    expect(receiver_target_obj).to include(
      'target_enabled' => true,
      'delivery_method_enabled' => true
    )

    as(SpecSeed.user) do
      json_post route_index_path, event_route: {
        label: 'Spec incidents',
        notification_receiver_id: receiver.id,
        event_type: 'vps.incident_report',
        continue: true
      }
    end

    expect_status(200)
    route = EventRoute.find(route_obj['id'])
    expect(route).to be_continue
    expect(route).to be_self_subject_scope
    expect(route_obj['subject_scope']).to eq('self')

    as(SpecSeed.user) do
      json_post matcher_index_path(route.id), matcher: {
        field: 'codename',
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
      payload: {
        'codename' => 'Spec-Abuse'
      }
    )

    as(SpecSeed.user) { json_get event_index_path }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to include(event.id)
    expect(events.find { |row| row['id'] == event.id }).not_to include('matched_event_route_id')

    as(SpecSeed.user) { json_get event_index_path, event: { event_route_id: route.id } }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    default_route = EventRoute.default_admin_route_for(SpecSeed.user)
    as(SpecSeed.user) { json_get event_index_path, event: { event_route_id: default_route.id } }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get event_index_path, event: { notification_receiver_id: receiver.id } }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get event_index_path, event: { notification_target_id: target.id } }

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) do
      json_get event_index_path, event: { notification_receiver_target_id: receiver_target.id }
    end

    expect_status(200)
    expect(events.map { |row| row['id'] }).to eq([event.id])

    as(SpecSeed.user) { json_get delivery_index_path(event.id) }

    expect_status(200)
    expect(deliveries.map { |row| row['action'] }).to eq(%w[webhook email])
    webhook_delivery_obj = deliveries.find { |row| row['action'] == 'webhook' }
    expect(webhook_delivery_obj['event_routing_context_id']).to be_present
    expect(webhook_delivery_obj['recipient_user_id']).to eq(SpecSeed.user.id)
    expect(webhook_delivery_obj['recipient_user_login']).to eq(SpecSeed.user.login)
    expect(webhook_delivery_obj['notification_receiver_id']).to eq(receiver.id)
    expect(webhook_delivery_obj['notification_receiver_label']).to eq('Spec receiver')
    expect(webhook_delivery_obj['notification_target_id']).to eq(target.id)
    expect(webhook_delivery_obj['notification_target_label']).to eq('Spec webhook')
    expect(webhook_delivery_obj['notification_target_display_target']).to eq('https://example.test/events')
    expect(webhook_delivery_obj['notification_receiver_target_id']).to eq(receiver_target.id)
    expect(webhook_delivery_obj['event_route_label']).to eq('Spec incidents')
    expect(webhook_delivery_obj['delivery_transaction_chain_id']).to be_nil
    expect(webhook_delivery_obj['delivery_transaction_chain_label']).to be_nil
    expect(webhook_delivery_obj).not_to include('template_name')

    delivery = event.event_deliveries.find_by!(action: 'webhook')

    as(SpecSeed.user) { json_get delivery_path(event.id, delivery.id) }

    expect_status(200)
    expect(delivery_obj['target_label']).to eq('Spec webhook')
    expect(delivery_obj['event_route_label']).to eq('Spec incidents')
    expect(delivery_obj['notification_receiver_label']).to eq('Spec receiver')
    expect(delivery_obj['notification_target_label']).to eq('Spec webhook')
    expect(delivery_obj).not_to include('template_name')

    as(SpecSeed.user) { json_get route_match_index_path(event.id) }
    expect_status(200)
    expect(route_matches.map { |row| row['event_route_id'] }).to eq([route.id, default_route.id])
    expect(route_matches.first).to include(
      'route_owner_id' => SpecSeed.user.id,
      'subject_relation' => 'self',
      'source' => 'direct_route'
    )

    as(SpecSeed.user) { json_get route_match_path(event.id, route_matches.first['id']) }
    expect_status(200)
    expect(json.dig('response', 'route_match', 'event_route_id')).to eq(route.id)

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

  it 'lets admins inspect visible events while users see only their delivery context' do
    receiver = NotificationReceiver.create!(user: SpecSeed.admin, label: 'Admin visible receiver')
    receiver_action = receiver.notification_receiver_actions.create!(
      action: :email,
      label: 'Admin default e-mail',
      target_kind: :default_recipient
    )
    route = EventRoute.create!(
      user: SpecSeed.admin,
      notification_receiver: receiver,
      event_type: 'user.test_notification',
      subject_scope: :visible,
      position: 1
    )
    route.event_route_matchers.create!(
      field: 'subject_relation',
      operator: '==',
      value: 'other_user'
    )

    event = VpsAdmin::API::Events.emit!(
      'user.test_notification',
      user: SpecSeed.user,
      subject: 'Spec visible event'
    )
    user_delivery = event.event_deliveries
                         .joins(:event_routing_context)
                         .find_by!(event_routing_contexts: { user_id: SpecSeed.user.id })
    admin_delivery = event.event_deliveries
                          .joins(:event_routing_context)
                          .find_by!(event_routing_contexts: { user_id: SpecSeed.admin.id })

    as(SpecSeed.admin) { json_get event_path(event.id) }
    expect_status(200)
    expect(event_obj['subject_relation']).to eq('other_user')
    expect(event_obj).not_to include('matched_event_route_id')

    as(SpecSeed.user) { json_get event_path(event.id) }
    expect_status(200)
    expect(event_obj['subject_relation']).to eq('self')
    expect(event_obj).not_to include('matched_event_route_id')

    as(SpecSeed.other_user) { json_get event_path(event.id) }
    expect_status(404)

    as(SpecSeed.admin) { json_get event_index_path, event: { subject_relation: 'other_user' } }
    expect_status(200)
    expect(events.map { |row| row['id'] }).to include(event.id)

    as(SpecSeed.admin) { json_get event_index_path, event: { notification_receiver_id: receiver.id } }
    expect_status(200)
    expect(events.map { |row| row['id'] }).to include(event.id)

    as(SpecSeed.user) { json_get event_index_path, event: { notification_receiver_id: receiver.id } }
    expect_status(200)
    expect(events.map { |row| row['id'] }).not_to include(event.id)

    as(SpecSeed.user) do
      json_get event_index_path, event: { notification_target_id: receiver_action.notification_target_id }
    end
    expect_status(200)
    expect(events.map { |row| row['id'] }).not_to include(event.id)

    as(SpecSeed.user) { json_get event_index_path, event: { event_route_id: route.id } }
    expect_status(200)
    expect(events.map { |row| row['id'] }).not_to include(event.id)

    as(SpecSeed.admin) { json_get event_index_path, event: { event_route_id: route.id } }
    expect_status(200)
    expect(events.map { |row| row['id'] }).to include(event.id)

    as(SpecSeed.admin) { json_get route_match_index_path(event.id) }
    expect_status(200)
    expect(route_matches.map { |row| row['event_route_id'] }).to include(route.id)

    admin_route_match = route_matches.find { |row| row['event_route_id'] == route.id }
    as(SpecSeed.admin) { json_get route_match_path(event.id, admin_route_match['id']) }
    expect_status(200)
    expect(json.dig('response', 'route_match', 'route_owner_id')).to eq(SpecSeed.admin.id)

    as(SpecSeed.user) { json_get delivery_index_path(event.id) }
    expect_status(200)
    expect(deliveries.map { |row| row['id'] }).to eq([user_delivery.id])

    as(SpecSeed.admin) { json_get delivery_index_path(event.id) }
    expect_status(200)
    expect(deliveries.map { |row| row['id'] }).to contain_exactly(user_delivery.id, admin_delivery.id)
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
      payload: {}
    )
    common = {
      event:,
      notification_receiver: receiver,
      notification_target: receiver_action.notification_target,
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
      'notification_target_label' => 'Spec queue e-mail',
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
      template_name: 'vps_incident_report'
    )

    as(SpecSeed.user) do
      json_put route_path(route.id), event_route: {
        label: 'Renamed route'
      }
    end

    expect_status(200)
    expect(route.reload.template_name).to eq('vps_incident_report')

    as(SpecSeed.user) do
      json_put route_path(route.id), event_route: {
        event_type: 'vps.oom_report'
      }
    end

    expect_status(200)
    expect(route.reload.template_name).to be_nil

    route.update!(template_name: 'vps_oom_report')

    as(SpecSeed.user) do
      json_post matcher_index_path(route.id), matcher: {
        field: 'cgroup',
        operator: '==',
        value: '/system.slice/spec.service'
      }
    end

    expect_status(200)
    expect(route.reload.template_name).to be_nil

    matcher = route.event_route_matchers.sole
    route.update!(template_name: 'vps_oom_report')

    as(SpecSeed.user) do
      json_put matcher_path(route.id, matcher.id), matcher: {
        value: '/system.slice/other.service'
      }
    end

    expect_status(200)
    expect(route.reload.template_name).to be_nil

    route.update!(template_name: 'vps_oom_report')

    as(SpecSeed.user) { json_delete matcher_path(route.id, matcher.id) }

    expect_status(200)
    expect(route.reload.template_name).to be_nil
  end

  it 'rejects Telegram targets when Telegram is not configured' do
    as(SpecSeed.user) do
      json_post notification_target_index_path, notification_target: {
        action: 'telegram',
        label: 'Spec Telegram'
      }
    end

    expect(json['status']).to be(false)
    expect(NotificationTarget.where(user: SpecSeed.user, action: 'telegram')).to be_empty
  end

  it 'returns Telegram pairing metadata for pending targets' do
    allow(VpsAdmin::API::Notifications).to receive(:telegram_configured?).and_return(true)
    allow(VpsAdmin::API::Notifications::Config).to receive(:load).and_return(
      'telegram' => {
        'bot_username' => 'vpsadmin_aitherdev_bot'
      }
    )

    target = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'telegram',
      label: 'Spec Telegram',
      target_kind: 'custom'
    )
    target.generate_verification_token!

    as(SpecSeed.user) { json_get notification_target_path(target.id) }
    expect_status(200)
    token = target.reload.verification_token
    expect(target_obj).to include(
      'telegram_bot_name' => 'vpsadmin_aitherdev_bot',
      'telegram_bot_url' => 'https://t.me/vpsadmin_aitherdev_bot',
      'telegram_pairing_url' => "https://t.me/vpsadmin_aitherdev_bot?start=#{token}",
      'telegram_pairing_command' => "/start #{token}"
    )
  end

  it 'hides SMS verification codes and accepts them through confirmation' do
    allow(VpsAdmin::API::Notifications).to receive(:sms_configured?).and_return(true)

    target = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'sms',
      label: 'Spec SMS',
      target_kind: 'custom',
      target_value: '+420123456789'
    )
    target.generate_sms_verification_code!
    code = target[:verification_token]

    as(SpecSeed.user) { json_get notification_target_path(target.id) }
    expect_status(200)
    expect(code).to match(/\A[0-9]{6}\z/)
    expect(target_obj['verification_token']).to be_nil

    as(SpecSeed.user) do
      json_post "#{notification_target_path(target.id)}/confirm_sms_verification_code", notification_target: {
        code:
      }
    end

    expect_status(200)
    expect(NotificationTarget.find(target.id)).to be_verified
  end

  it 'automatically sends custom e-mail verification for user-created targets' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')
    allow(VpsAdmin::API::Notifications).to receive(:deliver_mail_log!).and_return({})

    target = nil
    expect do
      target = create_notification_target!(
        {
          action: 'email',
          label: 'Spec e-mail',
          target_kind: 'custom',
          target_value: 'audit@example.test'
        }
      )
    end.to change(MailLog, :count).by(1)

    target.reload
    expect(target).not_to be_verified
    expect(target[:verification_token]).to be_present
    expect(target.email_verification_sent_at).to be_present
    expect(target.email_verification_send_available?).to be(false)

    mail_log = MailLog.order(:id).last
    expect(mail_log.to).to eq('audit@example.test')
    expect(mail_log.text_plain).to include('https://webui.example.test/?')
  end

  it 'keeps user-created custom e-mail targets pending when automatic verification send fails' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')
    allow(VpsAdmin::API::Notifications).to receive(:deliver_mail_log!).and_raise('SMTP unavailable')

    target = create_notification_target!(
      {
        action: 'email',
        label: 'Spec e-mail',
        target_kind: 'custom',
        target_value: 'audit@example.test'
      }
    )

    target.reload
    expect(target).not_to be_verified
    expect(target[:verification_token]).to be_present
    expect(target.email_verification_sent_at).to be_nil
    expect(target.last_error).to eq('SMTP unavailable')
  end

  it 'automatically resends custom e-mail verification when a user changes the address' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')
    allow(VpsAdmin::API::Notifications).to receive(:deliver_mail_log!).and_return({})

    target = create_notification_target!(
      {
        action: 'email',
        label: 'Spec e-mail',
        target_kind: 'custom',
        target_value: 'audit@example.test'
      }
    )
    token = target[:verification_token]

    expect do
      as(SpecSeed.user) do
        json_put notification_target_path(target.id), notification_target: {
          target_value: 'ops@example.test'
        }
      end
    end.to change(MailLog, :count).by(1)

    expect_status(200)
    target.reload
    expect(target.target_value).to eq('ops@example.test')
    expect(target[:verification_token]).to be_present
    expect(target[:verification_token]).not_to eq(token)
    expect(target.email_verification_sent_at).to be_present

    mail_log = MailLog.order(:id).last
    expect(mail_log.to).to eq('ops@example.test')
  end

  it 'hides custom e-mail verification tokens and accepts verification links' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')
    allow(VpsAdmin::API::Notifications).to receive(:deliver_mail_log!).and_return({})

    target = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'email',
      label: 'Spec e-mail',
      target_kind: 'custom',
      target_value: 'audit@example.test'
    )
    target.generate_email_verification_token!
    token = target[:verification_token]

    expect(target).not_to be_verified
    expect(token).to be_present

    as(SpecSeed.user) { json_get notification_target_path(target.id) }
    expect_status(200)
    expect(target_obj['verification_token']).to be_nil

    expect do
      as(SpecSeed.user) { json_post notification_target_email_send_path(target.id), {} }
    end.to change(MailLog, :count).by(1)

    expect_status(200)
    mail_log = MailLog.order(:id).last
    expect(mail_log.to).to eq('audit@example.test')
    expect(mail_log.text_plain).to include('https://webui.example.test/?')

    expect(target.reload.email_verification_send_available?).to be(false)
    expect do
      as(SpecSeed.user) { json_post notification_target_email_send_path(target.id), {} }
    end.not_to change(MailLog, :count)
    expect(json['status']).to be(false)
    expect(last_response.body).to include('e-mail verification link was sent recently')

    as(SpecSeed.user) do
      json_post notification_target_email_confirm_path(target.id), notification_target: {
        token: 'invalid'
      }
    end
    expect(json['status']).to be(false)
    expect(target.reload).not_to be_verified

    as(SpecSeed.user) do
      json_post notification_target_email_confirm_path(target.id), notification_target: {
        token:
      }
    end

    expect_status(200)
    expect(target.reload).to be_verified
    expect(target[:verification_token]).to be_nil
  end

  it 'auto-verifies custom e-mail and SMS targets saved by admins' do
    allow(VpsAdmin::API::Notifications).to receive(:sms_configured?).and_return(true)

    email_target = nil
    expect do
      email_target = create_notification_target!(
        {
          user: SpecSeed.user.id,
          action: 'email',
          label: 'Admin e-mail',
          target_kind: 'custom',
          target_value: 'admin-managed@example.test'
        },
        actor: SpecSeed.admin
      )
    end.not_to change(MailLog, :count)
    sms_target = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'sms',
      label: 'Admin SMS',
      target_kind: 'custom',
      target_value: '+420123456789'
    )
    sms_target.generate_sms_verification_code!

    expect(email_target).to be_verified
    expect(email_target[:verification_token]).to be_nil

    email_target.update!(verified_at: nil, verification_token: 'stale-token')
    as(SpecSeed.admin) do
      json_put notification_target_path(email_target.id), notification_target: {
        target_value: 'admin-managed-updated@example.test'
      }
    end

    expect_status(200)
    expect(email_target.reload).to be_verified
    expect(email_target[:verification_token]).to be_nil

    as(SpecSeed.admin) do
      json_put notification_target_path(sms_target.id), notification_target: {
        target_value: '+420123456780'
      }
    end

    expect_status(200)
    expect(sms_target.reload).to be_verified
    expect(sms_target[:verification_token]).to be_nil
  end

  it 'rejects targets when the delivery method is disabled for the user' do
    SpecSeed.user.set_notification_delivery_method!(:webhook, false)

    as(SpecSeed.user) do
      json_post notification_target_index_path, notification_target: {
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      }
    end

    expect(json['status']).to be(false)
    expect(errors.fetch('action')).to include('is not enabled for this user')
    expect(NotificationTarget.where(user: SpecSeed.user, action: 'webhook')).to be_empty
  end

  it 'auto-enables a delivery method when admin creates a target' do
    SpecSeed.user.set_notification_delivery_method!(:webhook, false)

    as(SpecSeed.admin) do
      json_post notification_target_index_path, notification_target: {
        user: SpecSeed.user.id,
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      }
    end

    expect_status(200)
    expect(json['status']).to be(true), last_response.body
    expect(SpecSeed.user.reload.notification_delivery_method_enabled?(:webhook)).to be(true)
    expect(NotificationTarget.where(user: SpecSeed.user).sole.action).to eq('webhook')
  end

  it 'does not auto-enable a delivery method when admin target create fails' do
    SpecSeed.user.set_notification_delivery_method!(:webhook, false)

    as(SpecSeed.admin) do
      json_post notification_target_index_path, notification_target: {
        user: SpecSeed.user.id,
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'not a URL'
      }
    end

    expect(json['status']).to be(false)
    expect(errors.fetch('target_value')).to include('must be an HTTP or HTTPS URL')
    expect(SpecSeed.user.reload.notification_delivery_method_enabled?(:webhook)).to be(false)
    expect(NotificationTarget.where(user: SpecSeed.user, action: 'webhook')).to be_empty
  end

  it 'does not auto-enable a delivery method when admin target update fails' do
    target = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'webhook',
      label: 'Spec webhook',
      target_kind: 'custom',
      target_value: 'https://example.test/events'
    )
    SpecSeed.user.set_notification_delivery_method!(:webhook, false)

    as(SpecSeed.admin) do
      json_put notification_target_path(target.id), notification_target: {
        target_value: 'not a URL'
      }
    end

    expect(json['status']).to be(false)
    expect(errors.fetch('target_value')).to include('must be an HTTP or HTTPS URL')
    expect(SpecSeed.user.reload.notification_delivery_method_enabled?(:webhook)).to be(false)
    expect(target.reload.target_value).to eq('https://example.test/events')
  end

  it 'skips lazy default e-mail actions when the delivery method is disabled' do
    SpecSeed.user.set_notification_delivery_method!(:email, false)
    event = nil

    expect do
      event = VpsAdmin::API::Events.emit!(
        'user.test_notification',
        user: SpecSeed.user,
        subject: 'Spec disabled default e-mail event'
      )
    end.to change(Event, :count).by(1)
    receiver = default_email_receiver_for(SpecSeed.user)
    route = EventRoute.default_route_for(SpecSeed.user)
    action = receiver.notification_receiver_actions.sole
    delivery = event.event_deliveries.sole

    expect(action.action).to eq('email')
    expect(event.reload).to be_suppressed_routing_state
    expect(event.event_route_matches.reload.map(&:event_route)).to include(route)
    expect(delivery).to be_skipped_state
    expect(delivery.action).to eq('email')
    expect(delivery.notification_receiver).to eq(receiver)
    expect(delivery.error_summary).to eq('delivery method is disabled')
  end

  it 'skips existing receiver targets when their delivery method is disabled' do
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
    receiver.notification_receiver_actions.create!(
      action: :webhook,
      label: 'Spec webhook',
      target_kind: :custom,
      target_value: 'https://example.test/events'
    )
    route = EventRoute.create!(
      user: SpecSeed.user,
      notification_receiver: receiver,
      event_type: 'user.test_notification'
    )

    SpecSeed.user.set_notification_delivery_method!(:webhook, false)
    event = nil

    expect do
      event = VpsAdmin::API::Events.emit!(
        'user.test_notification',
        user: SpecSeed.user,
        subject: 'Spec disabled delivery event'
      )
    end.to change(Event, :count).by(1)
    delivery = event.event_deliveries.sole

    expect(event.reload).to be_suppressed_routing_state
    expect(event.event_route_matches.reload.map(&:event_route)).to include(route)
    expect(delivery).to be_skipped_state
    expect(delivery.action).to eq('webhook')
    expect(delivery.notification_receiver).to eq(receiver)
    expect(delivery.error_summary).to eq('delivery method is disabled')
  end

  it 'lets users retry failed deliveries' do
    event = Event.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      category: 'test',
      severity: 'info',
      subject: 'Retryable delivery',
      payload: {}
    )
    delivery = EventDelivery.create!(
      event:,
      event_routing_context: create_delivery_context!(event),
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
      payload: {}
    )
    delivery = EventDelivery.create!(
      event:,
      event_routing_context: create_delivery_context!(event),
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

    create_linked_target!(
      receiver,
      {
        action: 'webhook',
        label: 'Spec webhook',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      }
    )

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

    expect(event.event_route_matches.reload.map(&:event_route)).to include(route)
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

  it 'limits receiver and target fan-out' do
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

    NotificationReceiverTarget::MAX_TARGETS_PER_RECEIVER.times do |i|
      target = NotificationTarget.create!(
        user: SpecSeed.user,
        action: :email,
        label: "E-mail #{i}",
        target_kind: :custom,
        target_value: "spec-#{i}@example.test"
      )
      receiver.notification_receiver_targets.create!(
        notification_target: target,
        position: i
      )
    end

    as(SpecSeed.user) do
      target = NotificationTarget.create!(
        user: SpecSeed.user,
        action: 'webhook',
        label: 'Too many actions',
        target_kind: 'custom',
        target_value: 'https://example.test/events'
      )
      json_post receiver_target_index_path(receiver.id), target: {
        notification_target_id: target.id
      }
    end

    expect(json['status']).to be(false)
  end

  it 'lists event types and fields' do
    as(SpecSeed.user) { json_get event_types_path }

    expect_status(200)
    incident = event_types.detect { |row| row['name'] == 'vps.incident_report' }
    incident_fields = incident['fields'].index_by { |field| field['name'] }
    expect(incident).to be_present
    expect(incident['default_routed']).to be(true)
    expect(incident_fields.dig('default_routed', 'type')).to eq('boolean')
    expect(incident_fields.dig('codename', 'description')).to eq('Incident report codename assigned by vpsAdmin')
    expect(incident_fields.dig('codename', 'type')).to eq('string')
    expect(incident_fields.dig('codename', 'operators')).to include('==', '=~')
    test = event_types.detect { |row| row['name'] == 'user.test_notification' }
    expect(test['default_routed']).to be(true)
    oom = event_types.detect { |row| row['name'] == 'vps.oom_report' }
    oom_fields = oom['fields'].index_by { |field| field['name'] }
    expect(oom_fields.dig('stage', 'description')).to eq('Processing stage that emitted the OOM notification')
    expect(oom_fields.dig('cgroups', 'type')).to eq('string_list')
    expect(oom_fields.dig('cgroups', 'operators')).to eq(%w[contains not_contains])
    chain = event_types.detect { |row| row['name'] == 'transaction_chain.state_changed' }
    chain_fields = chain['fields'].index_by { |field| field['name'] }
    expect(chain['default_routed']).to be(false)
    expect(chain_fields.dig('terminal', 'description')).to eq('Whether the chain reached a terminal state')
    expect(chain_fields.dig('terminal', 'type')).to eq('boolean')
    expect(chain_fields.dig('successful', 'type')).to eq('boolean')
    expect(chain_fields.dig('failed', 'type')).to eq('boolean')
    dns = event_types.detect { |row| row['name'] == 'dns.zone_transfer.failed' }
    expect(dns['default_routed']).to be(false)
  end

  it 'lists monitoring event types and fields registered by configuration', requires_plugins: :monitoring do
    VpsAdmin::API::Plugins::Monitoring::Events.register_event(
      'monitoring.spec_alert',
      label: 'Spec monitoring alert',
      template: :alert_monitoring_spec,
      monitors: %i[spec_alert],
      fields: %i[vps]
    )

    as(SpecSeed.user) { json_get event_types_path }

    expect_status(200)
    monitoring = event_types.detect { |row| row['name'] == 'monitoring.spec_alert' }
    monitoring_fields = monitoring['fields'].index_by { |field| field['name'] }
    expect(monitoring['default_routed']).to be(true)
    expect(monitoring_fields.dig('monitor_name', 'description')).to eq('Internal name of the monitor definition')
    expect(monitoring_fields.dig('state', 'description')).to eq('State of the monitored event after the check')
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
        payload_json: JSON.dump(note: 'from spec')
      }
    end

    expect_status(200)
    expect(event_obj['event_type']).to eq('user.test_notification')
    expect(event_obj['subject']).to eq('Spec test event')

    event = Event.find(event_obj['id'])
    expect(event.user).to eq(SpecSeed.user)
    expect(event.parameters).to eq('note' => 'from spec', 'roles' => ['account'])
    expect(event.source_class).to eq(VpsAdmin::API::Resources::Event::Test::TEST_EVENT_SOURCE_CLASS)
    expect(event.event_deliveries.map(&:action)).to eq(['email'])
  end

  it 'lets admins create visible test events for their visible routes' do
    receiver = NotificationReceiver.create!(user: SpecSeed.admin, label: 'Admin visible test receiver')
    receiver.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value: 'https://example.test/admin-visible-test'
    )
    route = EventRoute.create!(
      user: SpecSeed.admin,
      notification_receiver: receiver,
      event_type: 'user.test_notification',
      subject_scope: :visible,
      position: 1
    )

    as(SpecSeed.admin) do
      json_post event_test_path, event: {
        user: SpecSeed.user.id,
        subject_scope: 'visible',
        event_type: 'user.test_notification',
        subject: 'Spec visible test event'
      }
    end

    expect_status(200)
    event = Event.find(event_obj['id'])
    match = event.event_route_matches.sole
    delivery = event.event_deliveries.sole

    expect(event.user).to eq(SpecSeed.user)
    expect(match.event_route).to eq(route)
    expect(match.route_owner).to eq(SpecSeed.admin)
    expect(match.subject_relation).to eq('other_user')
    expect(delivery.event_route).to eq(route)
    expect(delivery.recipient_user).to eq(SpecSeed.admin)
  end

  it 'lets admins create system test events for their visible routes' do
    receiver = NotificationReceiver.create!(user: SpecSeed.admin, label: 'Admin system test receiver')
    receiver.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value: 'https://example.test/admin-system-test'
    )
    route = EventRoute.create!(
      user: SpecSeed.admin,
      notification_receiver: receiver,
      event_type: 'user.test_notification',
      subject_scope: :visible,
      position: 1
    )
    route.event_route_matchers.create!(
      field: 'subject_relation',
      operator: '==',
      value: 'system'
    )

    as(SpecSeed.admin) do
      json_post event_test_path, event: {
        subject_scope: 'system',
        event_type: 'user.test_notification',
        subject: 'Spec system test event'
      }
    end

    expect_status(200)
    event = Event.find(event_obj['id'])
    match = event.event_route_matches.sole

    expect(event.user).to be_nil
    expect(match.event_route).to eq(route)
    expect(match.route_owner).to eq(SpecSeed.admin)
    expect(match.subject_relation).to eq('system')
  end

  it 'does not let users create visible test events' do
    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          subject_scope: 'visible',
          subject: 'user visible test'
        }
      end
    end.not_to change(Event, :count)

    expect(json['status']).to be(false)
  end

  it 'rate-limits test events' do
    VpsAdmin::API::Resources::Event::Test::TEST_EVENT_LIMIT.times do |i|
      Event.create!(
        user: SpecSeed.user,
        event_type: 'user.test_notification',
        category: 'test',
        severity: 'info',
        subject: "Existing test event #{i}",
        payload: {},
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
    allow(VpsAdmin::API::Notifications).to receive_messages(
      telegram_configured?: true,
      sms_configured?: true
    )
    allow(VpsAdmin::API::Notifications::Config).to receive(:load).and_return(sms_notifications_config)

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
    receiver.notification_receiver_actions.create!(
      action: :telegram,
      label: 'Spec detail Telegram',
      target_kind: :custom,
      target_value: '123456',
      verified_at: Time.now
    )
    receiver.notification_receiver_actions.create!(
      action: :sms,
      label: 'Spec detail SMS',
      target_kind: :custom,
      target_value: '+420123456789',
      verified_at: Time.now
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
      payload: { note: 'delivery detail' }
    )
    email_delivery = event.event_deliveries.email_action.sole
    webhook_delivery = event.event_deliveries.webhook_action.sole
    telegram_delivery = event.event_deliveries.telegram_action.sole
    sms_delivery = event.event_deliveries.sms_action.sole
    email_delivery.update!(template_name: 'spec_internal_template')
    webhook_delivery.update!(
      response_status: 202,
      response_body: 'accepted',
      response_headers: { 'x-spec-detail' => ['delivery'] }
    )
    telegram_delivery.update!(
      response_status: 200,
      response_body: JSON.dump(ok: true, result: { message_id: 42 })
    )
    sms_delivery.update!(
      response_status: 202,
      response_body: JSON.dump(id: 101, status: 'queued')
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

    as(SpecSeed.user) { json_get delivery_path(event.id, telegram_delivery.id) }

    expect_status(200)
    telegram_payload = JSON.parse(delivery_obj['payload'])
    expect(telegram_payload['chat_id']).to eq('123456')
    expect(telegram_payload['text']).to include('Spec delivery detail event')
    expect(delivery_obj['response_body']).to include('"ok":true')

    as(SpecSeed.user) { json_get delivery_path(event.id, sms_delivery.id) }

    expect_status(200)
    sms_stored_payload = JSON.parse(sms_delivery.reload.payload)
    sms_payload = JSON.parse(delivery_obj['payload'])
    expect(sms_stored_payload['callback_secret']).to be_present
    expect(sms_payload['to']).to eq('+420123456789')
    expect(sms_payload['callback_secret']).to be_nil

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

  it 'lets admins inspect direct delivery attempts without a routing context' do
    event = Event.create!(
      event_type: 'incident_report.reply',
      category: 'incidents',
      severity: :info,
      subject: 'Direct incident reply',
      routing_state: :routed
    )
    delivery = event.event_deliveries.create!(
      action: :email,
      target_kind: :custom,
      target_value: 'sender@test.invalid',
      target_label: 'sender@test.invalid',
      state: :released
    )
    attempt = delivery.event_delivery_attempts.create!(
      action: delivery.action,
      state: :failed,
      attempt_number: 1,
      error_summary: 'smtp rejected'
    )

    as(SpecSeed.admin) { json_get delivery_attempt_index_path(event.id, delivery.id) }
    expect_status(200)
    expect(attempts.map { |row| row['id'] }).to eq([attempt.id])
    expect(attempts.first['error_summary']).to eq('smtp rejected')

    as(SpecSeed.admin) do
      json_get vpath("/events/#{event.id}/deliveries/#{delivery.id}/attempts/#{attempt.id}")
    end
    expect_status(200)
    attempt_obj = json.dig('response', 'attempt') ||
                  json.dig('response', 'event_delivery_attempt') ||
                  json['response']
    expect(attempt_obj['id']).to eq(attempt.id)

    as(SpecSeed.user) { json_get delivery_attempt_index_path(event.id, delivery.id) }
    expect_status(200)
    expect(attempts).to eq([])

    as(SpecSeed.user) do
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
        payload_json: JSON.dump(attempt_group_ids: [[other_attempt.id]])
      }
    end

    expect_status(200)
    failed_logins_event = Event.find(event_obj['id'])
    expect(VpsAdmin::API::Events.template_options_for(failed_logins_event).fetch(:vars).fetch(:attempt_groups)).to eq([[]])

    as(SpecSeed.user) do
      json_post event_test_path, event: {
        event_type: 'user.totp_recovery_code_used',
        subject: 'foreign totp id',
        payload_json: JSON.dump(totp_device_id: other_totp.id)
      }
    end

    expect_status(200)
    totp_event = Event.find(event_obj['id'])
    expect(VpsAdmin::API::Events.template_options_for(totp_event).fetch(:vars).fetch(:totp_device)).to be_nil
  end

  it 'rejects oversized test-event parameters' do
    expect do
      as(SpecSeed.user) do
        json_post event_test_path, event: {
          subject: 'oversized parameters',
          payload_json: JSON.dump(note: 'x' * ::Event::MAX_PARAMETERS_JSON_SIZE)
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
          payload_json: JSON.dump(['nope'])
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
