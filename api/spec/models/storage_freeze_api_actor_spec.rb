# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

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
      run.update_columns(record_contract: 2)
      expect { abandon(run) }.to raise_error(StorageMaintenanceRun::UnsupportedRecord)
      expect { described_class.show_maintenance_for_user!(request_id:, user: admin, user_session: session) }
        .to raise_error(StorageMaintenanceRun::UnsupportedRecord)
      scope = run.requested_scope_json
      run.update_columns(record_contract: 1, requested_scope_json: '{}')
      expect { abandon(run) }.to raise_error(StorageMaintenanceRun::UnsupportedRecord)
      run.update_columns(requested_scope_json: scope, freeze_epoch: epoch + 1)
      expect { abandon(run, expected_epoch: epoch) }.to raise_error(StorageMutationAdmission::MaintenanceConflict)
      expect(StorageFreezeControl.singleton!.active_maintenance_run_id).to eq(run.id)
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
        workers: [], release_queues: [], request_ids: [], owned_sessions: [],
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
  end
end
