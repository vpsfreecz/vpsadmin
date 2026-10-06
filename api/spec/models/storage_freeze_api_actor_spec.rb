# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'vpsadmin/storage_reconciler'

RSpec.describe StorageMutationAdmission do
  def session_for(admin)
    create_open_session!(user: admin, auth_type: 'basic')
  end

  def freeze!(admin:, session:, epoch:)
    described_class.set_read_only_for_user!(
      read_only: true, expected_epoch: epoch, reason: 'planned maintenance',
      user: admin, user_session: session
    )
  end

  it 'copies the locked direct administrator and session into the transition' do
    admin = SpecSeed.admin
    session = session_for(admin)
    epoch = StorageFreezeControl.singleton!.epoch

    freeze!(admin:, session:, epoch:)

    event = StorageFreezeTransition.order(:id).last
    expect(event).to have_attributes(
      actor_user_id: admin.id, actor_user_login: admin.login,
      actor_user_session_id: session.id
    )
    expect(event).not_to respond_to(:operator_uid)
    expect(StorageFreezeControl.singleton!.requested_by_user_id).to eq(admin.id)
  end

  it 'refuses a closed, delegated, or suspended session before changing mode' do
    admin = SpecSeed.admin
    session = session_for(admin)
    epoch = StorageFreezeControl.singleton!.epoch
    previous_events = StorageFreezeTransition.count

    session.update_columns(closed_at: Time.current)
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    session.update_columns(closed_at: nil, admin_id: admin.id)
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    session.update_columns(admin_id: nil)
    admin.update_columns(object_state: User.object_states.fetch(:suspended))
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_write', epoch:)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'serializes concurrent API freeze requests at one expected epoch', :no_transaction do
    admin = SpecSeed.admin
    session = session_for(admin)
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: 0)
    epoch = control.epoch
    previous_events = StorageFreezeTransition.count
    ready = Queue.new
    go = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          begin
            freeze!(admin:, session:, epoch:)
            :changed
          rescue StorageMutationAdmission::StaleEpoch
            :stale
          end
        end
      end
    end
    Timeout.timeout(5) { 2.times { ready.pop } }
    2.times { go << true }
    expect(Timeout.timeout(5) { threads.map(&:value) }).to contain_exactly(:changed, :stale)
    expect(StorageFreezeTransition.count).to eq(previous_events + 1)
    expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: epoch + 1)
  ensure
    2.times { go << true } if go
    threads&.each { |thread| thread.join(5) }
    StorageFreezeTransition.where(new_epoch: epoch + 1).delete_all if epoch
    StorageFreezeControl.singleton!.update_columns(mode: 0, epoch:) if epoch
  end

  context 'with current requested actor eligibility' do
    let(:actor) do
      create_lifecycle_user!.tap { |user| user.update_columns(level: SpecSeed.admin.level) }
    end
    let(:session) { session_for(actor) }
    let(:epoch) { StorageFreezeControl.singleton!.epoch }

    before do
      StorageFreezeControl.singleton!.update_columns(mode: 0)
      session
    end

    it 'allows absent history for the confirmed active direct actor' do
      ObjectState.where(class_name: 'User', row_id: actor.id).delete_all
      expect(actor.current_object_state).to be_nil

      freeze!(admin: actor, session:, epoch:)

      expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: epoch + 1)
    end

    it 'allows the latest active request for the confirmed active direct actor' do
      request = record_requested_user_state!(actor, :active)
      expect(actor.current_object_state.id).to eq(request.id)

      freeze!(admin: actor, session:, epoch:)

      expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: epoch + 1)
    end

    %i[suspended soft_delete hard_delete deleted].each do |state|
      it "refuses a latest #{state} request while the confirmed actor remains active" do
        record_requested_user_state!(actor, state)
        control = StorageFreezeControl.singleton!.attributes
        transitions = StorageFreezeTransition.count

        expect { freeze!(admin: actor, session:, epoch:) }
          .to raise_error(described_class::AuthorizationRefused)

        expect(actor.reload.object_state).to eq('active')
        expect(StorageFreezeControl.singleton!.attributes).to eq(control)
        expect(StorageFreezeTransition.count).to eq(transitions)
      end
    end

    it 'refuses a present unknown state instead of treating its nil enum as absent' do
      request = record_requested_user_state!(actor, :active)
      request.update_columns(state: 99)
      expect(actor.current_object_state).to have_attributes(id: request.id, state: nil)
      control = StorageFreezeControl.singleton!.attributes

      expect { freeze!(admin: actor, session:, epoch:) }
        .to raise_error(described_class::AuthorizationRefused)

      expect(StorageFreezeControl.singleton!.attributes).to eq(control)
    end

    %i[suspended soft_delete].each do |state|
      %i[show abandon].each do |action|
        it "refuses maintenance #{action} for a latest #{state} request without changing its owner" do
          StorageFreezeControl.singleton!.update_columns(mode: 1)
          run = described_class.reserve_maintenance_for_user!(
            request_id: SecureRandom.uuid, expected_epoch: epoch, pool_ids: [SpecSeed.pool.id],
            reason: 'requested-state authority', user: actor, user_session: session
          )
          before = run.attributes
          control = StorageFreezeControl.singleton!.attributes
          record_requested_user_state!(actor, state)

          expect do
            if action == :show
              described_class.show_maintenance_for_user!(request_id: run.request_id, user: actor, user_session: session)
            else
              described_class.abandon_maintenance_for_user!(
                request_id: run.request_id, expected_epoch: epoch, expected_revision: 1,
                expected_scope_digest: run.requested_scope_digest, reason: 'unused requested-state owner',
                user: actor, user_session: session
              )
            end
          end.to raise_error(described_class::AuthorizationRefused)

          expect(run.reload.attributes).to eq(before)
          expect(StorageFreezeControl.singleton!.attributes).to eq(control)
        end
      end
    end

    it 'keeps default and explicit false query SQL identical and locks only on opt-in' do
      request = record_requested_user_state!(actor, :active)
      selects = []
      subscriber = lambda do |*, payload|
        selects << payload[:sql] if payload[:sql].match?(/\bFROM `object_states`(?:\s|$)/)
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        ActiveRecord::Base.uncached do
          expect(actor.current_object_state.id).to eq(request.id)
          expect(actor.current_object_state(lock: false).id).to eq(request.id)
          User.transaction do
            actor.lock!
            expect(actor.current_object_state(lock: true).id).to eq(request.id)
          end
        end
      end

      expect(selects.length).to eq(3)
      expect(selects[0]).to eq(selects[1])
      expect(selects[0]).not_to include('FOR UPDATE')
      expect(selects[2]).to end_with('FOR UPDATE')
    end

    it 'uses the latest timestamp before the higher ID under default and locking lookup' do
      timestamp = (ObjectState.where(class_name: 'User', row_id: actor.id).maximum(:created_at) || Time.current) + 1
      newest = record_requested_user_state!(actor, :active)
      newest.update_columns(created_at: timestamp + 1)
      older = record_requested_user_state!(actor, :suspended)
      older.update_columns(created_at: timestamp)
      expect(older.id).to be > newest.id

      expect(actor.current_object_state.id).to eq(newest.id)
      User.transaction do
        actor.lock!
        expect(actor.current_object_state(lock: true).id).to eq(newest.id)
      end
    end

    it 'isolates class and row and breaks equal timestamps by ID under both lookups' do
      timestamp = (ObjectState.where(class_name: 'User', row_id: actor.id).maximum(:created_at) || Time.current) + 1
      older = record_requested_user_state!(actor, :active)
      latest = record_requested_user_state!(actor, :suspended)
      [older, latest].each { |request| request.update_columns(created_at: timestamp) }
      ObjectState.create!(class_name: 'Vps', row_id: actor.id, state: :active,
                          user: actor, created_at: timestamp + 1)
      other = create_lifecycle_user!
      record_requested_user_state!(other, :active).update_columns(created_at: timestamp + 1)
      expect(latest.id).to be > older.id

      expect(actor.current_object_state.id).to eq(latest.id)
      User.transaction do
        actor.lock!
        expect(actor.current_object_state(lock: true).id).to eq(latest.id)
      end
    end

    it 'rejects non-Boolean locking options instead of accepting SQL lock strings' do
      [nil, 'FOR UPDATE', 1, :update].each do |lock|
        expect { actor.current_object_state(lock:) }
          .to raise_error(ArgumentError, 'invalid object-state lock option')
      end
    end
  end

  context 'with an API-only storage maintenance reservation' do
    let(:admin) { SpecSeed.admin }
    let(:session) { create_open_session!(user: admin, auth_type: 'basic') }
    let(:request_id) { SecureRandom.uuid }
    let(:epoch) { StorageFreezeControl.singleton!.epoch }

    before { StorageFreezeControl.singleton!.update_columns(mode: 1) }

    def reserve(**overrides)
      StorageMutationAdmission.reserve_maintenance_for_user!(
        request_id:, expected_epoch: epoch, pool_ids: [SpecSeed.pool.id],
        reason: 'API reservation', user: admin, user_session: session, **overrides
      )
    end

    def abandon(run, **overrides)
      StorageMutationAdmission.abandon_maintenance_for_user!(
        request_id: run.request_id, expected_epoch: run.freeze_epoch,
        expected_revision: 1, expected_scope_digest: run.requested_scope_digest,
        reason: 'abandon unused API reservation', user: admin, user_session: session, **overrides
      )
    end

    def refuse_locked_control_update!(message)
      allow(StorageFreezeControl).to receive(:lock).and_wrap_original do |lock, *args|
        relation = lock.call(*args)
        allow(relation).to receive(:find).with(1).and_wrap_original do |find, *ids|
          control = find.call(*ids)
          allow(control).to receive(:update!).and_raise(message)
          control
        end
        relation
      end
    end

    it 'copies the locked catalog and acquiring actor without dispatching or changing freeze audit' do
      SpecSeed.pool.update_columns(zpool_guid: 18_446_744_073_709_551_615)
      control_before = StorageFreezeControl.singleton!.attributes.except('active_maintenance_run_id', 'updated_at')
      before = [TransactionChain.count, Transaction.count, StorageFreezeTransition.count,
                StorageMutationIntent.count, StorageIntegrityScope.count, Pool.count, Node.count]
      allow(VpsAdmin::API::TransactionSigner).to receive(:sign_base64) do
        raise 'prohibited signing during API reservation'
      end
      allow(TransactionChains::Storage::Inventory).to receive(:fire) do
        raise 'prohibited Node dispatch during API reservation'
      end

      run = reserve

      expect(run).to have_attributes(record_contract: 1, state: 'reserved', revision: 1,
                                     requested_profile: 'manual_storage_only_v1', freeze_epoch: epoch,
                                     acquired_by_user_id: admin.id, acquired_by_user_session_id: session.id,
                                     acquired_by_user_login: admin.login)
      expect(run.requested_scope.fetch('pools')).to eq(
        [
          { 'pool_id' => SpecSeed.pool.id, 'node_id' => SpecSeed.pool.node_id,
            'pool_role' => SpecSeed.pool.role, 'filesystem' => SpecSeed.pool.filesystem,
            'node_role' => SpecSeed.pool.node.role, 'hypervisor_type' => SpecSeed.pool.node.hypervisor_type,
            'zpool_guid' => '18446744073709551615' }
        ]
      )
      expect(run.requested_scope_digest).to eq(Digest::SHA256.hexdigest(run.requested_scope_json))
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
      expect(StorageFreezeControl.singleton!.attributes.except('active_maintenance_run_id', 'updated_at'))
        .to eq(control_before)
      expect([TransactionChain.count, Transaction.count, StorageFreezeTransition.count,
              StorageMutationIntent.count, StorageIntegrityScope.count, Pool.count, Node.count]).to eq(before)
      expect(run.summary).not_to have_key(:requested_scope_json)
      expect(VpsAdmin::API::TransactionSigner).not_to have_received(:sign_base64)
      expect(TransactionChains::Storage::Inventory).not_to have_received(:fire)
    end

    it 'keeps unknown GUIDs null and sorts the exact requested Pool IDs' do
      pool = create_pool!(node: SpecSeed.node, role: :backup)
      run = reserve(pool_ids: [pool.id, SpecSeed.pool.id])

      expect(run.summary[:requested_pool_ids]).to eq([pool.id, SpecSeed.pool.id].sort)
      expect(run.requested_scope['pools'].map { |claim| claim['zpool_guid'] }).to all(be_nil)
    end

    it 'returns an exact active UUID replay without changing audit or pointer' do
      run = reserve(reason: '  API reservation  ')
      before = run.attributes
      expect(reserve.id).to eq(run.id)
      expect(run.reload.attributes).to eq(before)
      expect(StorageMaintenanceRun.count).to eq(1)
    end

    it 'refuses UUID replay with a changed session, reason, catalog or requested set' do
      run = reserve
      other = create_open_session!(user: admin, auth_type: 'basic')
      [{ user_session: other }, { reason: 'changed' }, { pool_ids: [SpecSeed.pool.id, 2_000_000_000] }].each do |attrs|
        expect { reserve(**attrs) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      end
      SpecSeed.pool.update_columns(filesystem: 'changed/catalog')
      expect { reserve }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
      expect(StorageMaintenanceRun.count).to eq(1)
    end

    it 'rejects closed, delegated, suspended and nonadmin actors without reserving' do
      session.update_columns(closed_at: Time.current)
      expect { reserve }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      session.update_columns(closed_at: nil, admin_id: admin.id)
      expect { reserve }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      session.update_columns(admin_id: nil)
      admin.update_columns(object_state: User.object_states.fetch(:suspended))
      expect { reserve }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      admin.update_columns(object_state: User.object_states.fetch(:active))
      member_session = create_open_session!(user: SpecSeed.user, auth_type: 'basic')
      expect { reserve(user: SpecSeed.user, user_session: member_session) }
        .to raise_error(StorageMutationAdmission::AuthorizationRefused)
      expect(StorageMaintenanceRun.count).to eq(0)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to be_nil
    end

    it 'rejects invalid UUID, pool shape, missing IDs and stale epoch atomically' do
      invalid_ids = [nil, [], [0], [-1], ['1'], [1.0], [true], [nil], [[1]], [{ 'id' => 1 }],
                     [SpecSeed.pool.id, SpecSeed.pool.id], (1..257).to_a]
      invalid_ids.each do |ids|
        expect { reserve(pool_ids: ids) }.to raise_error(ArgumentError)
      end
      ['bad', 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA', nil].each do |id|
        expect { reserve(request_id: id) }.to raise_error(ArgumentError)
      end
      expect { reserve(pool_ids: [2_000_000_000]) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect { reserve(expected_epoch: epoch + 1) }.to raise_error(StorageMutationAdmission::StaleEpoch)
      expect(StorageMaintenanceRun.count).to eq(0)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to be_nil
    end

    it 'snapshots all 256 requested live Pools without truncation or synthetic claims' do
      pools = [SpecSeed.pool] + Array.new(255) { create_pool!(node: SpecSeed.node, role: :primary) }
      run = reserve(pool_ids: pools.map(&:id).reverse)
      expect(run.summary[:requested_pool_ids]).to eq(pools.map(&:id).sort)
      expect(run.requested_scope['pools'].length).to eq(256)
    end

    it 'rolls back abandonment audit when clearing the singleton fails' do
      run = reserve
      before = run.attributes
      refuse_locked_control_update!('injected pointer clear failure')
      expect { abandon(run) }.to raise_error('injected pointer clear failure')
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'requires read-only mode and refuses a different active owner' do
      StorageFreezeControl.singleton!.update_columns(mode: 0)
      expect { reserve }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      StorageFreezeControl.singleton!.update_columns(mode: 1)
      run = reserve
      expect { reserve(request_id: SecureRandom.uuid) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'rolls back both creation and publication on a before-commit failure' do
      refuse_locked_control_update!('injected publication failure')
      expect { reserve }.to raise_error('injected publication failure')
      expect(StorageMaintenanceRun.count).to eq(0)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to be_nil
    end

    it 'retains immutable acquisition and terminal audits and rejects model deletion' do
      run = reserve
      saved = run.attributes
      expect { run.update!(acquisition_reason: 'rewritten') }.to raise_error(ActiveRecord::RecordInvalid)
      expect { run.reload.update!(requested_scope_digest: 'a' * 64) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(run.reload.attributes).to eq(saved)
      expect { run.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      abandon(run)
      expect { run.reload.update!(abandonment_reason: 'rewritten') }.to raise_error(ActiveRecord::RecordInvalid)
      expect(run.reload.acquisition_reason).to eq(saved['acquisition_reason'])
    end

    it 'audits a fresh administrator after actor death while leaving mode and epoch unchanged' do
      run = reserve
      session.update_columns(closed_at: Time.current)
      other_admin = SpecSeed.support
      other_admin.update_columns(level: 90)
      replacement = create_open_session!(user: other_admin, auth_type: 'basic')
      before = StorageFreezeControl.singleton!.attributes.except('active_maintenance_run_id', 'updated_at')
      transitions = StorageFreezeTransition.count
      abandoned = abandon(run, user: other_admin, user_session: replacement)
      expect(abandoned).to have_attributes(state: 'abandoned', revision: 2,
                                           acquired_by_user_session_id: session.id,
                                           abandoned_by_user_session_id: replacement.id,
                                           abandoned_by_user_id: other_admin.id,
                                           abandoned_by_user_login: other_admin.login)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to be_nil
      expect(StorageFreezeControl.singleton!.attributes.except('active_maintenance_run_id', 'updated_at')).to eq(before)
      expect(StorageFreezeTransition.count).to eq(transitions)
    end

    it 'replays only the same terminal abandonment while no new owner exists' do
      run = reserve
      terminal = abandon(run).attributes
      expect(abandon(run).attributes).to eq(terminal)
      expect { abandon(run, reason: 'changed') }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect { reserve }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      next_run = reserve(request_id: SecureRandom.uuid)
      expect { abandon(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(next_run.id)
    end

    it 'refuses stale revision, scope and epoch without clearing the owner' do
      run = reserve
      before = run.attributes
      expect { abandon(run, expected_revision: 2) }.to raise_error(ArgumentError)
      expect { abandon(run, expected_revision: 1.0) }.to raise_error(ArgumentError)
      expect { abandon(run, expected_scope_digest: 'a' * 64) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect { abandon(run, expected_epoch: epoch + 1) }.to raise_error(StorageMutationAdmission::StaleEpoch)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'fails closed on unknown contracts, malformed scope and inconsistent owner state' do
      run = reserve
      expect { run.update_columns(record_contract: 2) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(StorageMaintenanceRun.supported_tuple?(3, 'reserved', 1)).to be(false)
      scope = run.reload.requested_scope_json
      run.update_columns(requested_scope_json: '{}')
      expect { described_class.show_maintenance_for_user!(request_id:, user: admin, user_session: session) }
        .to raise_error(StorageMaintenanceRun::UnsupportedRecord)
      expect { abandon(run) }.to raise_error(StorageMaintenanceRun::UnsupportedRecord)
      run.update_columns(requested_scope_json: scope, freeze_epoch: epoch + 1)
      expect { abandon(run, expected_epoch: epoch) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end
  end

  context 'with pre-transition responsibility acknowledgement' do
    let(:admin) { SpecSeed.admin }
    let(:session) { create_open_session!(user: admin, auth_type: 'basic') }
    let(:epoch) { StorageFreezeControl.singleton!.epoch }
    let(:request_id) { SecureRandom.uuid }

    before { StorageFreezeControl.singleton!.update_columns(mode: 1) }

    def reserve_for_handoff
      described_class.reserve_maintenance_for_user!(
        request_id:, expected_epoch: epoch, pool_ids: [SpecSeed.pool.id],
        reason: 'API reservation', user: admin, user_session: session
      )
    end

    def acknowledge(run, **overrides)
      described_class.handoff_maintenance_for_user!(
        request_id: run.request_id, expected_epoch: epoch, expected_contract: 1, expected_revision: 1,
        expected_scope_digest: run.requested_scope_digest, reason: 'prospective responsibility',
        user: admin, user_session: session, **overrides
      )
    end

    it 'changes only the exact tuple and handoff audit without dispatch or physical effects' do
      run = reserve_for_handoff
      before = run.attributes
      control = StorageFreezeControl.singleton!.attributes
      counts = [TransactionChain.count, Transaction.count, StorageFreezeTransition.count,
                StorageMutationIntent.count, StorageIntegrityScope.count, Pool.count, Node.count]
      allow(VpsAdmin::API::TransactionSigner).to receive(:sign_base64) { raise 'prohibited handoff signing' }
      allow(TransactionChains::Storage::Inventory).to receive(:fire) { raise 'prohibited handoff dispatch' }
      allow(VpsAdmin::StorageReconciler::Capture).to receive(:new) { raise 'prohibited handoff capture' }
      allow(VpsAdmin::StorageReconciler::NodeTransport).to receive(:new) { raise 'prohibited handoff transport' }
      result = acknowledge(run, reason: '  prospective responsibility  ')
      expect(result).to have_attributes(record_contract: 2, state: 'handoff_pending', revision: 2,
                                        handed_off_by_user_id: admin.id, handed_off_by_user_session_id: session.id,
                                        handed_off_by_user_login: admin.login, handoff_reason: 'prospective responsibility')
      expect(result.handed_off_at).not_to be_nil
      expect(result.attributes.except('record_contract', 'state', 'revision', *StorageMaintenanceRun::HANDOFF_FIELDS))
        .to eq(before.except('record_contract', 'state', 'revision', *StorageMaintenanceRun::HANDOFF_FIELDS))
      expect(StorageFreezeControl.singleton!.attributes).to eq(control)
      expect([TransactionChain.count, Transaction.count, StorageFreezeTransition.count,
              StorageMutationIntent.count, StorageIntegrityScope.count, Pool.count, Node.count]).to eq(counts)
      expect(VpsAdmin::API::TransactionSigner).not_to have_received(:sign_base64)
      expect(TransactionChains::Storage::Inventory).not_to have_received(:fire)
      expect(VpsAdmin::StorageReconciler::Capture).not_to have_received(:new)
      expect(VpsAdmin::StorageReconciler::NodeTransport).not_to have_received(:new)
      expect(result.summary).not_to have_key(:requested_scope_json)
    end

    it 'copies a fresh accepting direct administrator separately from the acquisition actor' do
      run = reserve_for_handoff
      fresh = SpecSeed.support
      fresh.update_columns(level: 90)
      fresh_session = create_open_session!(user: fresh, auth_type: 'basic')
      result = acknowledge(run, user: fresh, user_session: fresh_session)
      expect(result).to have_attributes(acquired_by_user_id: admin.id, acquired_by_user_session_id: session.id,
                                        handed_off_by_user_id: fresh.id, handed_off_by_user_session_id: fresh_session.id,
                                        handed_off_by_user_login: fresh.login)
      expect(described_class.show_maintenance_for_user!(request_id:, user: admin, user_session: session).attributes)
        .to eq(result.attributes)
    end

    it 'replays the original CAS without changing audit or revalidating the catalog' do
      run = reserve_for_handoff
      result = acknowledge(run).attributes
      SpecSeed.pool.update_columns(filesystem: 'spec/changed-after-handoff')
      writes = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        writes << payload[:sql] if payload[:sql].match?(/\A\s*(?:UPDATE|INSERT|DELETE)\b/i)
      end
      begin
        expect(acknowledge(run).attributes).to eq(result)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      expect(writes).to be_empty
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'refuses changed replay bindings and successor CAS without changing responsibility' do
      run = reserve_for_handoff
      result = acknowledge(run).attributes
      other = create_open_session!(user: admin, auth_type: 'basic')
      [{ user_session: other }, { reason: 'different' }, { expected_scope_digest: 'a' * 64 },
       { request_id: SecureRandom.uuid }].each do |attrs|
        expect { acknowledge(run, **attrs) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      end
      expect { acknowledge(run, expected_epoch: epoch + 1) }.to raise_error(StorageMutationAdmission::StaleEpoch)
      expect { acknowledge(run, expected_contract: 2) }.to raise_error(ArgumentError)
      expect { acknowledge(run, expected_revision: 2) }.to raise_error(ArgumentError)
      expect(run.reload.attributes).to eq(result)
    end

    it 'requires exact integer predecessor CAS and safe reason before changing the owner' do
      run = reserve_for_handoff
      before = run.attributes
      [nil, true, '1', 1.0, 0, 2].each do |value|
        expect { acknowledge(run, expected_contract: value) }.to raise_error(ArgumentError)
        expect { acknowledge(run, expected_revision: value) }.to raise_error(ArgumentError)
      end
      [nil, '', ' ' * 3, 'x' * 256, "bad\nreason"].each do |reason|
        expect { acknowledge(run, reason:) }.to raise_error(ArgumentError)
      end
      expect(StorageMaintenanceRun.supported_tuple?(1.0, 'reserved', 1)).to be(false)
      expect(StorageMaintenanceRun.active_tuple?(2, 'handoff_pending', 2.0)).to be(false)
      expect(run.reload.attributes).to eq(before)
    end

    it 'refuses current Pool and Node claim changes before handoff' do
      run = reserve_for_handoff
      before = run.attributes
      pool = SpecSeed.pool
      filesystem = pool.filesystem
      pool.update_columns(filesystem: 'spec/changed-before-handoff')
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      pool.update_columns(filesystem:)
      node = pool.node
      node.update_columns(role: Node.roles.fetch('mailer'))
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'refuses a missing requested Pool and preserves the exact owner' do
      pool = create_pool!(node: SpecSeed.node, role: :backup)
      run = described_class.reserve_maintenance_for_user!(
        request_id:, expected_epoch: epoch, pool_ids: [pool.id], reason: 'API reservation',
        user: admin, user_session: session
      )
      before = run.attributes
      pool.delete
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'refuses a missing requested Node without dropping its retained catalog claim' do
      node = create_node!(role: :storage)
      pool = create_pool!(node:, role: :backup)
      run = described_class.reserve_maintenance_for_user!(
        request_id:, expected_epoch: epoch, pool_ids: [pool.id], reason: 'API reservation',
        user: admin, user_session: session
      )
      before = run.attributes
      node.delete
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'refuses a missing pointer or inconsistent owner epoch before adding handoff audit' do
      run = reserve_for_handoff
      before = run.attributes
      control = StorageFreezeControl.singleton!
      control.update_columns(active_maintenance_run_id: nil)
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.attributes).to eq(before)
      control.update_columns(active_maintenance_run_id: run.id)
      run.update_columns(freeze_epoch: epoch + 1)
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.handed_off_at).to be_nil
      expect(control.reload.active_maintenance_run_id).to eq(run.id)
    end

    it 'revalidates closed, delegated, suspended and nonadmin actors before responsibility changes' do
      run = reserve_for_handoff
      before = run.attributes
      session.update_columns(closed_at: Time.current)
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      session.update_columns(closed_at: nil, admin_id: admin.id)
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      session.update_columns(admin_id: nil)
      admin.update_columns(object_state: User.object_states.fetch(:suspended))
      expect { acknowledge(run) }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      admin.update_columns(object_state: User.object_states.fetch(:active))
      member_session = create_open_session!(user: SpecSeed.user, auth_type: 'basic')
      expect { acknowledge(run, user: SpecSeed.user, user_session: member_session) }
        .to raise_error(StorageMutationAdmission::AuthorizationRefused)
      expect(run.reload.attributes).to eq(before)
    end

    it 'never abandons, reopens or deletes a handoff owner' do
      run = reserve_for_handoff
      before = acknowledge(run).attributes
      [1, 2].each do |revision|
        error = revision == 1 ? StorageMutationAdmission::MaintenanceConflict : ArgumentError
        expect do
          described_class.abandon_maintenance_for_user!(
            request_id:, expected_epoch: epoch, expected_revision: revision,
            expected_scope_digest: run.requested_scope_digest, reason: 'not safely API-only', user: admin, user_session: session
          )
        end.to raise_error(error)
      end
      expect { reserve_for_handoff }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.destroy).to be(false)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'keeps every handoff audit and acquisition value immutable after acknowledgement' do
      run = acknowledge(reserve_for_handoff)
      before = run.attributes
      (StorageMaintenanceRun::HANDOFF_FIELDS + StorageMaintenanceRun::ACQUISITION_FIELDS).each do |field|
        changed = run.reload.attributes[field]
        changed = if changed.is_a?(Integer) || changed.is_a?(Time)
                    changed + 1
                  else
                    "changed-#{changed}"
                  end
        expect { run.update!(field => changed) }.to raise_error(ActiveRecord::RecordInvalid)
      end
      expect { run.reload.update!(record_contract: 1, state: 'reserved', revision: 1) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(run.reload.attributes).to eq(before)
    end

    it 'refuses partial handoff audit and direct creation of a successor record' do
      run = reserve_for_handoff
      audit = { record_contract: 2, state: 'handoff_pending', revision: 2,
                handed_off_by_user_id: admin.id, handed_off_by_user_session_id: session.id,
                handed_off_by_user_login: admin.login, handoff_reason: 'prospective responsibility',
                handed_off_at: Time.current }
      before = run.attributes
      StorageMaintenanceRun::HANDOFF_FIELDS.each do |field|
        expect { run.reload.update!(audit.merge(field.to_sym => nil)) }.to raise_error(ActiveRecord::RecordInvalid)
      end
      fresh = StorageMaintenanceRun.new(before.except('id').merge(audit.stringify_keys))
      expect { fresh.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(run.reload.attributes).to eq(before)
      expect(StorageMaintenanceRun.where(request_id:).count).to eq(1)
    end

    it 'rolls back a failure after the actual run update but before transaction commit' do
      run = reserve_for_handoff
      before = run.attributes
      control = StorageFreezeControl.singleton!.attributes
      allow(StorageMaintenanceRun).to receive(:lock).and_wrap_original do |lock, *args|
        relation = lock.call(*args)
        allow(relation).to receive(:find_by).with(id: run.id).and_wrap_original do |find, *ids|
          current = find.call(*ids)
          allow(current).to receive(:update!).and_wrap_original do |update, *values|
            update.call(*values)
            raise 'handoff precommit failure'
          end
          current
        end
        relation
      end
      expect { acknowledge(run) }.to raise_error('handoff precommit failure')
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.attributes).to eq(control)
    end
  end

  context 'with committed API maintenance authority', :no_transaction do
    # Every worker borrows a distinct ordinary connection, checks the test-owned
    # database binding, and disconnects it before fixture restoration.
    def reservation_worker(&operation)
      state = { closed: false, acquired: false }
      database = ActiveRecord::Base.connection.select_value('SELECT DATABASE()')
      parent_id = ActiveRecord::Base.connection.select_value('SELECT CONNECTION_ID()')
      state[:thread] = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          state[:acquired] = true
          begin
            unless connection.select_value('SELECT DATABASE()') == database &&
                   connection.select_value('SELECT CONNECTION_ID()') != parent_id
              raise 'reservation worker database binding refused'
            end

            connection.execute('SET SESSION innodb_lock_wait_timeout = 2')
            operation.call(connection)
          ensure
            connection.disconnect!
            state[:closed] = true
          end
        end
      end
      reservation_state.fetch(:workers) << state
      state[:thread]
    end

    let(:reservation_state) do
      control_before = StorageFreezeControl.singleton!.attributes
      {
        workers: [], release_queues: [], request_ids: [], owned_sessions: [], owned_object_state_ids: [],
        control_before:, transition_ids_before: StorageFreezeTransition.pluck(:id),
        epoch: control_before.fetch('epoch')
      }
    end

    around do |example|
      fixture = reservation_state
      StorageFreezeControl.singleton!.update_columns(mode: 1)
      primary = nil
      begin
        example.run
      rescue Exception => e # rubocop:disable Lint/RescueException
        primary = e
        raise
      ensure
        fixture.fetch(:release_queues).each { |queue| 2.times { queue << true } }
        worker_error = nil
        fixture.fetch(:workers).each do |state|
          thread = state.fetch(:thread)
          begin
            thread.join(3)
          rescue Exception => e # rubocop:disable Lint/RescueException
            worker_error ||= e
          end
          next unless thread.alive?

          thread.kill
          begin
            thread.join(3)
          rescue Exception => e # rubocop:disable Lint/RescueException
            worker_error ||= e
          end
        end
        reaped = fixture.fetch(:workers).all? do |state|
          !state.fetch(:thread).alive? && (!state[:acquired] || state[:closed])
        end
        unless reaped
          RSpec.world.wants_to_quit = true
          raise(primary || 'reservation reader not reaped; fixture restoration refused')
        end
        begin
          StorageFreezeControl.singleton!.update_columns(fixture.fetch(:control_before).except('id'))
          StorageMaintenanceRun.where(request_id: fixture.fetch(:request_ids)).delete_all
          StorageFreezeTransition.where.not(id: fixture.fetch(:transition_ids_before)).delete_all
          ObjectState.where(id: fixture.fetch(:owned_object_state_ids)).delete_all
          fixture.fetch(:owned_sessions).each(&:destroy!)
          raise worker_error if worker_error
        rescue Exception # rubocop:disable Lint/RescueException
          raise primary if primary

          raise
        end
      end
    end

    def committed_session
      session = create_open_session!(user: SpecSeed.admin, auth_type: 'basic')
      reservation_state.fetch(:owned_sessions) << session
      session
    end

    def committed_reserve(session:, request_id: nil)
      request_id ||= SecureRandom.uuid.tap { |id| reservation_state.fetch(:request_ids) << id }
      StorageMutationAdmission.reserve_maintenance_for_user!(
        request_id:, expected_epoch: reservation_state.fetch(:epoch),
        pool_ids: [SpecSeed.pool.id], reason: 'committed API reservation',
        user: SpecSeed.admin, user_session: session
      )
    end

    def committed_handoff(run, session:)
      described_class.handoff_maintenance_for_user!(
        request_id: run.request_id, expected_epoch: reservation_state.fetch(:epoch),
        expected_contract: 1, expected_revision: 1, expected_scope_digest: run.requested_scope_digest,
        reason: 'committed prospective responsibility', user: SpecSeed.admin, user_session: session
      )
    end

    %i[suspended soft_delete].each do |requested_state|
      %i[freeze unfreeze catch_up reserve handoff].each do |action|
        it "refuses #{action} after a committed #{requested_state} request despite an older repeatable-read view" do
          session = committed_session
          admin = SpecSeed.admin
          active_request = User.transaction do
            actor = User.lock.find(admin.id)
            record_requested_user_state!(actor, :active).tap do |request|
              reservation_state.fetch(:owned_object_state_ids) << request.id
            end
          end
          StorageFreezeControl.singleton!.update_columns(mode: action == :freeze ? 0 : 1)
          run = committed_reserve(session:) if action == :handoff
          snapshot = lambda do
            {
              control: StorageFreezeControl.singleton!.attributes,
              runs: StorageMaintenanceRun.order(:id).map(&:attributes),
              transitions: StorageFreezeTransition.order(:id).map(&:attributes),
              catch_up_audits: StorageObserverCatchUpAudit.order(:id).map(&:attributes)
            }
          end
          before = ActiveRecord::Base.uncached { snapshot.call }
          request_id = SecureRandom.uuid
          reservation_state.fetch(:request_ids) << request_id
          committed = nil
          ActiveRecord::Base.transaction do
            connection = ActiveRecord::Base.connection
            expect(connection.select_value('SELECT @@tx_isolation')).to eq('REPEATABLE-READ')
            ActiveRecord::Base.uncached do
              expect(admin.current_object_state).to have_attributes(id: active_request.id, state: 'active')
            end
            writer = reservation_worker do |worker_connection|
              expect(worker_connection.select_value('SELECT @@tx_isolation')).to eq('REPEATABLE-READ')
              User.transaction do
                actor = User.lock.find(admin.id)
                request = record_requested_user_state!(actor, requested_state, actor:)
                reservation_state.fetch(:owned_object_state_ids) << request.id
                current_session = UserSession.find(session.id)
                [request.id, request.state, actor.object_state, current_session.closed_at, current_session.admin_id]
              end
            end
            committed = Timeout.timeout(5) { writer.value }
            expect(committed.drop(1)).to eq([requested_state.to_s, 'active', nil, nil])
            ActiveRecord::Base.uncached do
              expect(admin.current_object_state).to have_attributes(id: active_request.id, state: 'active')
            end
            writes = []
            locked_tables = []
            subscriber = lambda do |*, payload|
              sql = payload.fetch(:sql)
              statement = sql[/\A\s*(\w+)/, 1]&.upcase
              writes << statement if %w[INSERT UPDATE DELETE REPLACE CREATE ALTER DROP TRUNCATE RENAME].include?(statement)
              if sql.include?('FOR UPDATE')
                locked_tables.concat(sql.scan(/\bFROM `(storage_freeze_controls|users|user_sessions|object_states)`/).flatten)
              end
            end
            ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
              expect do
                case action
                when :freeze, :unfreeze
                  described_class.set_read_only_for_user!(
                    read_only: action == :freeze, expected_epoch: reservation_state.fetch(:epoch),
                    reason: 'current requested actor', user: admin, user_session: session
                  )
                when :catch_up
                  described_class.request_catch_up_for_user!(
                    user: admin, user_session: session, expected_epoch: reservation_state.fetch(:epoch),
                    reason: 'current requested actor', after_chain_id: 0, limit: 1
                  )
                when :reserve
                  committed_reserve(session:, request_id:)
                when :handoff
                  committed_handoff(run, session:)
                end
              end.to raise_error(described_class::AuthorizationRefused)
            end
            expect(writes).to be_empty
            expect(locked_tables).to eq(%w[storage_freeze_controls users user_sessions object_states])
          end
          ActiveRecord::Base.uncached do
            expect(admin.current_object_state).to have_attributes(id: committed.first, state: requested_state.to_s)
            expect(admin.reload.object_state).to eq('active')
            expect(session.reload).to have_attributes(closed_at: nil, admin_id: nil)
            expect(snapshot.call).to eq(before)
          end
        end
      end
    end

    it 'publishes a lost-response UUID to an ordinary second connection and releases the lock' do
      session = committed_session
      run = committed_reserve(session:)
      reader = reservation_worker do |connection|
        connection.transaction do
          control = StorageFreezeControl.lock.find(1)
          found = described_class.show_maintenance_for_user!(
            request_id: run.request_id, user: SpecSeed.admin, user_session: session
          )
          [control.active_maintenance_run_id, found.id, found.requested_scope_digest]
        end
      end
      expect(Timeout.timeout(5) { reader.value }).to eq([run.id, run.id, run.requested_scope_digest])
      expect(committed_reserve(session:, request_id: run.request_id).id).to eq(run.id)
    end

    it 'serializes two reservations and publishes only one owner' do
      session = committed_session
      ready = Queue.new
      go = Queue.new
      reservation_state.fetch(:release_queues) << go
      workers = 2.times.map do
        id = SecureRandom.uuid
        reservation_state.fetch(:request_ids) << id
        reservation_worker do
          ready << true
          go.pop
          begin
            committed_reserve(session:, request_id: id)
            :reserved
          rescue StorageMutationAdmission::MaintenanceConflict
            :conflict
          end
        end
      end
      Timeout.timeout(5) { 2.times { ready.pop } }
      2.times { go << true }
      expect(Timeout.timeout(5) { workers.map(&:value) }).to contain_exactly(:reserved, :conflict)
      expect(StorageMaintenanceRun.where(request_id: reservation_state.fetch(:request_ids)).count).to eq(1)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to be > 0
    end

    it 'serializes reserve against read-write so the losing operation cannot bypass the owner' do
      session = committed_session
      ready = Queue.new
      go = Queue.new
      reservation_state.fetch(:release_queues) << go
      id = SecureRandom.uuid
      reservation_state.fetch(:request_ids) << id
      reserving = reservation_worker do
        ready << true
        go.pop
        begin
          committed_reserve(session:, request_id: id)
          :reserved
        rescue StorageMutationAdmission::StaleEpoch, StorageMutationAdmission::MaintenanceConflict
          :reservation_refused
        end
      end
      switching = reservation_worker do
        ready << true
        go.pop
        begin
          described_class.set_read_only_for_user!(
            read_only: false, expected_epoch: reservation_state.fetch(:epoch), reason: 'competing unfreeze',
            user: SpecSeed.admin, user_session: session
          )
          :unfrozen
        rescue StorageMutationAdmission::MaintenanceConflict
          :unfreeze_refused
        end
      end
      Timeout.timeout(5) { 2.times { ready.pop } }
      2.times { go << true }
      result = Timeout.timeout(5) { [reserving.value, switching.value] }
      expect(result).to eq(%i[reserved unfreeze_refused]).or eq(%i[reservation_refused unfrozen])
      control = StorageFreezeControl.singleton!
      if control.active_maintenance_run_id
        expect(control).to have_attributes(mode: 'read_only', epoch: reservation_state.fetch(:epoch))
      else
        expect(control).to have_attributes(mode: 'read_write', epoch: reservation_state.fetch(:epoch) + 1)
      end
    end

    it 'keeps a committed owner after session closure and permits separately audited abandonment' do
      session = committed_session
      run = committed_reserve(session:)
      session.update_columns(closed_at: Time.current)
      replacement = committed_session
      reader = reservation_worker do
        described_class.abandon_maintenance_for_user!(
          request_id: run.request_id, expected_epoch: reservation_state.fetch(:epoch), expected_revision: 1,
          expected_scope_digest: run.requested_scope_digest, reason: 'unused owner recovered',
          user: SpecSeed.admin, user_session: replacement
        ).summary
      end
      result = Timeout.timeout(5) { reader.value }
      expect(result).to include(state: 'abandoned', acquired_by_user_session_id: session.id,
                                abandoned_by_user_session_id: replacement.id)
      expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: reservation_state.fetch(:epoch),
                                                                 active_maintenance_run_id: nil)
    end

    it 'uses a current locked catalog read after a distinct connection commits a change' do
      session = committed_session
      filesystem = SpecSeed.pool.reload.filesystem
      ActiveRecord::Base.transaction do
        expect(Pool.find(SpecSeed.pool.id).filesystem).to eq(filesystem)
        changer = reservation_worker { Pool.find(SpecSeed.pool.id).update_columns(filesystem: 'spec/changed') }
        Timeout.timeout(5) { changer.value }
        run = committed_reserve(session:)
        expect(run.requested_scope['pools'].sole['filesystem']).to eq('spec/changed')
      end
    ensure
      reaped = reservation_state.fetch(:workers).all? do |state|
        !state[:thread].alive? && (!state[:acquired] || state[:closed])
      end
      SpecSeed.pool.update_columns(filesystem:) if filesystem && reaped
    end

    it 'publishes committed handoff audit to an ordinary reader and resolves a lost reply without another write' do
      session = committed_session
      run = committed_reserve(session:)
      expect do
        committed_handoff(run, session:)
        raise 'lost handoff response after commit'
      end.to raise_error('lost handoff response after commit')
      reader = reservation_worker do |connection|
        connection.transaction do
          control = StorageFreezeControl.lock.find(1)
          found = described_class.show_maintenance_for_user!(request_id: run.request_id,
                                                             user: SpecSeed.admin, user_session: session)
          [control.active_maintenance_run_id, found.attributes]
        end
      end
      pointer, observed = Timeout.timeout(5) { reader.value }
      expect(pointer).to eq(run.id)
      expect(observed).to include('record_contract' => 2, 'state' => 'handoff_pending', 'revision' => 2,
                                  'handed_off_by_user_session_id' => session.id)
      expect(committed_handoff(run, session:).attributes).to eq(observed)
      expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: reservation_state.fetch(:epoch))
    end

    it 'serializes handoff against abandonment without partial audit or pointer loss' do
      session = committed_session
      run = committed_reserve(session:)
      ready = Queue.new
      go = Queue.new
      reservation_state.fetch(:release_queues) << go
      handing_off = reservation_worker do
        ready << true
        go.pop
        begin
          committed_handoff(run, session:)
          :handed_off
        rescue StorageMutationAdmission::MaintenanceConflict
          :handoff_refused
        end
      end
      abandoning = reservation_worker do
        ready << true
        go.pop
        begin
          described_class.abandon_maintenance_for_user!(
            request_id: run.request_id, expected_epoch: reservation_state.fetch(:epoch), expected_revision: 1,
            expected_scope_digest: run.requested_scope_digest, reason: 'competing unused reservation',
            user: SpecSeed.admin, user_session: session
          )
          :abandoned
        rescue StorageMutationAdmission::MaintenanceConflict
          :abandon_refused
        end
      end
      Timeout.timeout(5) { 2.times { ready.pop } }
      2.times { go << true }
      result = Timeout.timeout(5) { [handing_off.value, abandoning.value] }
      expect(result).to eq(%i[handed_off abandon_refused]).or eq(%i[handoff_refused abandoned])
      current = run.reload
      control = StorageFreezeControl.singleton!
      expect(control).to have_attributes(mode: 'read_only', epoch: reservation_state.fetch(:epoch))
      if current.state == 'handoff_pending'
        expect(current).to have_attributes(record_contract: 2, revision: 2, handed_off_by_user_session_id: session.id,
                                           abandonment_reason: nil)
        expect(control.active_maintenance_run_id).to eq(current.id)
      else
        expect(current).to have_attributes(record_contract: 1, state: 'abandoned', revision: 2,
                                           handoff_reason: nil, abandoned_by_user_session_id: session.id)
        expect(control.active_maintenance_run_id).to be_nil
      end
    end

    it 'serializes handoff against unfreeze while retaining the responsible owner' do
      session = committed_session
      run = committed_reserve(session:)
      ready = Queue.new
      go = Queue.new
      reservation_state.fetch(:release_queues) << go
      handing_off = reservation_worker do
        ready << true
        go.pop
        committed_handoff(run, session:)
        :handed_off
      end
      switching = reservation_worker do
        ready << true
        go.pop
        begin
          described_class.set_read_only_for_user!(
            read_only: false, expected_epoch: reservation_state.fetch(:epoch), reason: 'competing unfreeze',
            user: SpecSeed.admin, user_session: session
          )
          :unfrozen
        rescue StorageMutationAdmission::MaintenanceConflict
          :unfreeze_refused
        end
      end
      Timeout.timeout(5) { 2.times { ready.pop } }
      2.times { go << true }
      expect(Timeout.timeout(5) { [handing_off.value, switching.value] }).to eq(%i[handed_off unfreeze_refused])
      expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: reservation_state.fetch(:epoch),
                                                                 active_maintenance_run_id: run.id)
    end

    it 'retains handoff responsibility after the accepting session closes' do
      session = committed_session
      run = committed_reserve(session:)
      before = committed_handoff(run, session:).attributes
      session.update_columns(closed_at: Time.current)
      replacement = committed_session
      reader = reservation_worker do
        described_class.show_maintenance_for_user!(request_id: run.request_id,
                                                   user: SpecSeed.admin, user_session: replacement).attributes
      end
      expect(Timeout.timeout(5) { reader.value }).to eq(before)
      expect { committed_handoff(run, session:) }.to raise_error(StorageMutationAdmission::AuthorizationRefused)
      expect do
        described_class.abandon_maintenance_for_user!(
          request_id: run.request_id, expected_epoch: reservation_state.fetch(:epoch), expected_revision: 1,
          expected_scope_digest: run.requested_scope_digest, reason: 'not safely API-only',
          user: SpecSeed.admin, user_session: replacement
        )
      end.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(run.reload.attributes).to eq(before)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    end

    it 'refuses a separately committed catalog change despite an older repeatable-read snapshot' do
      session = committed_session
      run = committed_reserve(session:)
      filesystem = SpecSeed.pool.reload.filesystem
      ActiveRecord::Base.transaction do
        expect(Pool.find(SpecSeed.pool.id).filesystem).to eq(filesystem)
        changer = reservation_worker { Pool.find(SpecSeed.pool.id).update_columns(filesystem: 'spec/handoff-changed') }
        Timeout.timeout(5) { changer.value }
        expect { committed_handoff(run, session:) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      end
      expect(run.reload).to have_attributes(record_contract: 1, state: 'reserved', revision: 1, handed_off_at: nil)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
    ensure
      reaped = reservation_state.fetch(:workers).all? do |state|
        !state[:thread].alive? && (!state[:acquired] || state[:closed])
      end
      SpecSeed.pool.update_columns(filesystem:) if filesystem && reaped
    end
  end
end
