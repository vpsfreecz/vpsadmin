# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::StorageFreeze' do
  before { header 'Accept', 'application/json' }

  def path(action = nil)
    vpath(['/storage_freeze', action].compact.join('/'))
  end

  def json_get
    get path, nil, 'CONTENT_TYPE' => 'application/json'
  end

  def json_post(action, attrs)
    post path(action), JSON.generate(storage_freeze: attrs),
         'CONTENT_TYPE' => 'application/json'
  end

  def as_token(user, scope: ['all'], admin: nil)
    session = create_open_session!(user:, admin:, auth_type: 'token',
                                   token_lifetime: 'permanent', scope:)
    header 'X-HaveAPI-Auth-Token', session.token.token
    yield
  ensure
    header 'X-HaveAPI-Auth-Token', nil
  end

  def as_admin(&block)
    as_token(SpecSeed.admin, &block)
  end

  def status
    json.dig('response', 'storage_freeze') || json['response']
  end

  def expect_status(code)
    expect(last_response.status).to eq(code), last_response.body
  end

  it 'publishes separate action scopes for the singular resource' do
    scopes = EndpointInventory.scopes_for_version(self, api_version)
    expect(scopes).to include(
      'storage_freeze#show', 'storage_freeze#read_only',
      'storage_freeze#read_write', 'storage_freeze#settle_observer'
    )
  end

  it 'allows only an active direct administrator to see status' do
    json_get
    expect_status(401)
    as_token(SpecSeed.user) { json_get }
    expect_status(403)
    as_token(SpecSeed.support) { json_get }
    expect_status(403)

    as_admin { json_get }
    expect_status(200)
    expect(status).to include(
      'mode' => 'read_write', 'db_drained' => false,
      'repair_ready' => false, 'counts' => a_kind_of(Hash),
      'count_capped' => a_kind_of(Array), 'observed_at' => a_kind_of(String)
    )
  end

  it 'rejects delegated admin sessions and action scopes without mutation' do
    admin = SpecSeed.admin
    previous_events = StorageFreezeTransition.count

    as_token(admin, admin:) do
      json_post('read_only', expected_epoch: 0, reason: 'maintenance')
    end
    expect_status(403)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'applies the framework action scope to each storage action' do
    admin = SpecSeed.admin
    previous_events = StorageFreezeTransition.count

    as_token(admin, scope: ['storage_freeze#show']) { json_get }
    expect_status(200)
    as_token(admin, scope: ['storage_freeze#show']) do
      json_post('read_only', expected_epoch: StorageFreezeControl.singleton!.epoch,
                             reason: 'maintenance')
    end
    expect_status(403)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'rejects a suspended administrator' do
    SpecSeed.admin.update_columns(object_state: User.object_states.fetch(:suspended))

    as_admin { json_get }

    expect_status(403)
  end

  it 'returns the entire bounded snapshot without running catch-up or writing SQL' do
    allow(StorageObserverSettlement).to receive(:catch_up!)
    statements = []
    listener = lambda do |_name, _started, _finished, _id, payload|
      statements << payload[:sql] if payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
      as_admin { json_get }
    end

    expect_status(200)
    expect(status.keys).to include(
      'mode', 'epoch', 'stable_epoch', 'counts', 'count_capped',
      'sample_chain_ids', 'sample_fatal_chain_ids', 'sample_intent_ids',
      'db_drained', 'repair_ready', 'reason', 'transition', 'observed_at'
    )
    expect(StorageObserverSettlement).not_to have_received(:catch_up!)
    expect(statements.grep(/\A\s*(INSERT|UPDATE|DELETE|REPLACE)\s+(?:INTO\s+)?`?storage_/i)).to be_empty
  end

  it 'requires a fresh epoch in both directions and records the admin identity' do
    initial_epoch = StorageFreezeControl.singleton!.epoch
    as_admin do
      json_post('read_only', expected_epoch: initial_epoch, reason: 'planned maintenance')
    end
    expect_status(200)
    frozen_epoch = status.fetch('epoch')
    control = StorageFreezeControl.singleton!
    event = StorageFreezeTransition.order(:id).last
    expect(control).to have_attributes(mode: 'read_only', epoch: frozen_epoch,
                                       requested_by_user_id: SpecSeed.admin.id)
    expect(event).to have_attributes(actor_user_id: SpecSeed.admin.id,
                                     actor_user_login: SpecSeed.admin.login)
    expect(status.fetch('transition').keys)
      .not_to include('actor_source', 'operator_uid', 'operator_login')
    expect(event.actor_user_session_id).to be > 0

    as_admin do
      json_post('read_write', expected_epoch: initial_epoch, reason: 'stale request')
    end
    expect_status(409)
    expect(StorageFreezeControl.singleton!.epoch).to eq(frozen_epoch)

    as_admin do
      json_post('read_write', expected_epoch: frozen_epoch, reason: 'maintenance complete')
    end
    expect_status(200)
    expect(StorageFreezeControl.singleton!).to have_attributes(
      mode: 'read_write', epoch: frozen_epoch + 1
    )
  end

  it 'returns conflict for a stale freeze' do
    epoch = StorageFreezeControl.singleton!.epoch
    previous_events = StorageFreezeTransition.count

    as_admin { json_post('read_only', expected_epoch: epoch + 1, reason: 'stale') }

    expect_status(409)
    expect(StorageFreezeControl.singleton!.epoch).to eq(epoch)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'returns conflict for an already selected mode' do
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: StorageFreezeControl.modes.fetch('read_only'))
    previous_events = StorageFreezeTransition.count

    as_admin do
      json_post('read_only', expected_epoch: control.epoch, reason: 'again')
    end

    expect_status(409)
    expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: control.epoch)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'requires an expected epoch for both mode changes and catch-up' do
    previous_transitions = StorageFreezeTransition.count
    previous_audits = StorageObserverCatchUpAudit.count

    as_admin { json_post('read_only', reason: 'maintenance') }
    expect_status(200)
    expect(json['status']).to be(false)
    expect(json.dig('errors', 'expected_epoch')).to include('required parameter is missing')
    as_admin { json_post('read_write', reason: 'maintenance complete') }
    expect_status(200)
    expect(json['status']).to be(false)
    expect(json.dig('errors', 'expected_epoch')).to include('required parameter is missing')
    as_admin { json_post('settle_observer', reason: 'review old node') }
    expect_status(200)
    expect(json['status']).to be(false)
    expect(json.dig('errors', 'expected_epoch')).to include('required parameter is missing')

    expect(StorageFreezeTransition.count).to eq(previous_transitions)
    expect(StorageObserverCatchUpAudit.count).to eq(previous_audits)
  end

  it 'keeps mode and epoch unchanged when transition insertion fails' do
    before = StorageFreezeControl.singleton!.attributes
    allow(StorageFreezeTransition).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    as_admin do
      json_post('read_only', expected_epoch: before.fetch('epoch'), reason: 'maintenance')
    end

    expect_status(500)
    expect(StorageFreezeControl.singleton!.attributes).to eq(before)
  end

  it 'records a frozen catch-up request and completion with the API actor' do
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: 1, epoch: control.epoch + 1)
    result = {
      scanned_chains: 0, settled_intents: 0, settled_chain_ids: [],
      blocked_chains: 0, blocked_chain_ids: [], blocked_reasons: {},
      after_chain_id: 0, next_after_chain_id: nil, has_more: false, limit: 2
    }
    allow(StorageObserverSettlement).to receive(:catch_up!) do
      expect(StorageObserverCatchUpAudit.event_requested.count).to eq(1)
      expect(StorageObserverCatchUpAudit.event_completed.count).to eq(0)
      result
    end

    as_admin do
      json_post('settle_observer', reason: 'review old node', expected_epoch: control.epoch,
                                   after_chain_id: 0, limit: 2)
    end

    expect_status(200)
    expect(StorageObserverSettlement).to have_received(:catch_up!).with(
      limit: 2, after_chain_id: 0, expected_epoch: control.epoch
    )
    events = StorageObserverCatchUpAudit.order(:id).to_a
    expect(events.map(&:event_type)).to eq(%w[requested completed])
    expect(events.map(&:request_id).uniq.length).to eq(1)
    expect(events).to all(have_attributes(actor_user_id: SpecSeed.admin.id,
                                          actor_user_login: SpecSeed.admin.login))
    expect(events.map(&:actor_user_session_id).uniq.length).to eq(1)
    expect(events.first.actor_user_session_id).to be > 0
    expect(status.fetch('audit_request_id')).to eq(events.first.request_id)
  end

  it 'rejects a stale catch-up epoch before writing a request audit' do
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: 1, epoch: control.epoch + 1)
    previous_audits = StorageObserverCatchUpAudit.count
    allow(StorageObserverSettlement).to receive(:catch_up!)

    as_admin do
      json_post('settle_observer', reason: 'review old node',
                                   expected_epoch: control.epoch - 1)
    end

    expect_status(409)
    expect(StorageObserverCatchUpAudit.count).to eq(previous_audits)
    expect(StorageObserverSettlement).not_to have_received(:catch_up!)
  end

  it 'retains the request event when the frozen epoch changes during catch-up' do
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: 1, epoch: control.epoch + 1)
    allow(StorageObserverSettlement).to receive(:catch_up!) do
      raise ArgumentError, 'catch-up freeze epoch changed'
    end

    as_admin do
      json_post('settle_observer', reason: 'review old node', expected_epoch: control.epoch)
    end

    expect_status(409)
    expect(StorageObserverCatchUpAudit.event_requested.count).to eq(1)
    expect(StorageObserverCatchUpAudit.event_completed.count).to eq(0)
  end
end
