require 'securerandom'

# The freeze row serializes new storage writers with a switch to read_only.
# Call while staging a chain, in the same SQL transaction as its writes.
class StorageMutationAdmission
  class StaleEpoch < StandardError; end
  class MaintenanceConflict < StandardError; end
  class SameMode < ArgumentError; end
  class AuthorizationRefused < StandardError; end

  def self.set_read_only_for_user!(read_only:, expected_epoch:, reason:, user:, user_session:)
    change_mode!(read_only:, expected_epoch:, reason:) do
      actor, session = locked_api_actor!(user:, user_session:)

      { actor_user_id: actor.id, actor_user_login: actor.login,
        actor_user_session_id: session.id,
        requested_by_user_id: actor.id }
    end
  end

  def self.request_catch_up_for_user!(user:, user_session:, expected_epoch:, reason:,
                                      after_chain_id:, limit:)
    validate_reason!(reason)
    validate_epoch!(expected_epoch, required: true)
    raise ArgumentError, 'invalid chain cursor' unless after_chain_id.is_a?(Integer) && after_chain_id >= 0
    raise ArgumentError, 'invalid catch-up limit' unless limit.is_a?(Integer) && limit.between?(1, 100)

    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      raise StaleEpoch, 'storage freeze epoch changed' unless control.epoch == expected_epoch
      raise SameMode, 'catch-up requires read-only mode' unless control.read_only?

      actor, session = locked_api_actor!(user:, user_session:)
      StorageObserverCatchUpAudit.create!(
        request_id: SecureRandom.uuid, event_type: :requested,
        actor_user_id: actor.id,
        actor_user_session_id: session.id, actor_user_login: actor.login,
        reason: reason.strip, freeze_epoch: control.epoch,
        after_chain_id:, page_limit: limit, created_at: Time.current
      )
    end
  end

  def self.reserve_maintenance_for_user!(request_id:, expected_epoch:, pool_ids:, reason:, user:, user_session:)
    StorageMaintenanceRun.request_id!(request_id)
    ids = StorageMaintenanceRun.pool_ids!(pool_ids)
    validate_epoch!(expected_epoch, required: true)
    validate_reason!(reason)

    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      actor, session = locked_api_actor!(user:, user_session:)
      validate_maintenance_control!(control, expected_epoch)
      owner = active_maintenance!(control)
      run = StorageMaintenanceRun.lock.find_by(request_id:)
      scope_json = locked_maintenance_scope!(ids)
      if run
        run.supported!
        unless owner&.id == run.id && run.state == 'reserved' &&
               run.freeze_epoch == expected_epoch && run.requested_scope_json == scope_json &&
               run.acquired_by_user_id == actor.id && run.acquired_by_user_session_id == session.id &&
               run.acquisition_reason == reason.strip
          raise MaintenanceConflict, 'maintenance request binding changed'
        end

        next run
      end
      raise MaintenanceConflict, 'storage maintenance already reserved' if owner

      run = StorageMaintenanceRun.new(
        request_id:, record_contract: StorageMaintenanceRun::RECORD_CONTRACT,
        requested_profile: StorageMaintenanceRun::REQUESTED_PROFILE,
        state: 'reserved', revision: StorageMaintenanceRun::REVISIONS.fetch('reserved'),
        freeze_epoch: control.epoch, requested_scope_json: scope_json,
        requested_scope_digest: Digest::SHA256.hexdigest(scope_json),
        acquired_by_user_id: actor.id, acquired_by_user_session_id: session.id,
        acquired_by_user_login: actor.login, acquisition_reason: reason.strip,
        acquired_at: Time.current
      )
      run.supported!
      run.save!
      control.update!(active_maintenance_run: run)
      run
    end
  end

  def self.show_maintenance_for_user!(request_id:, user:, user_session:)
    StorageMaintenanceRun.request_id!(request_id)
    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      locked_api_actor!(user:, user_session:)
      owner = active_maintenance!(control)
      run = StorageMaintenanceRun.lock.find_by(request_id:)
      raise MaintenanceConflict, 'maintenance request not found' unless run

      run.supported!
      if run.state == 'reserved' && owner&.id != run.id
        raise MaintenanceConflict, 'maintenance owner is inconsistent'
      end

      run
    end
  end

  def self.abandon_maintenance_for_user!(request_id:, expected_epoch:, expected_revision:,
                                         expected_scope_digest:, reason:, user:, user_session:)
    StorageMaintenanceRun.request_id!(request_id)
    validate_epoch!(expected_epoch, required: true)
    validate_reason!(reason)
    unless expected_revision.is_a?(Integer) && expected_revision == StorageMaintenanceRun::REVISIONS.fetch('reserved') &&
           expected_scope_digest.is_a?(String) && StorageMaintenanceRun::DIGEST_PATTERN.match?(expected_scope_digest)
      raise ArgumentError, 'invalid maintenance compare-and-swap'
    end

    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      actor, session = locked_api_actor!(user:, user_session:)
      validate_maintenance_control!(control, expected_epoch)
      owner = active_maintenance!(control)
      run = StorageMaintenanceRun.lock.find_by(request_id:)
      raise MaintenanceConflict, 'maintenance request not found' unless run

      run.supported!
      unless run.freeze_epoch == expected_epoch && run.requested_scope_digest == expected_scope_digest
        raise MaintenanceConflict, 'maintenance request binding changed'
      end

      if run.state == 'abandoned'
        unless owner.nil? && run.abandoned_by_user_id == actor.id &&
               run.abandoned_by_user_session_id == session.id && run.abandonment_reason == reason.strip
          raise MaintenanceConflict, 'maintenance abandonment binding changed'
        end

        next run
      end
      unless owner&.id == run.id && run.revision == expected_revision
        raise MaintenanceConflict, 'maintenance owner changed'
      end

      run.update!(state: 'abandoned', revision: StorageMaintenanceRun::REVISIONS.fetch('abandoned'),
                  abandoned_by_user_id: actor.id, abandoned_by_user_session_id: session.id,
                  abandoned_by_user_login: actor.login, abandonment_reason: reason.strip,
                  abandoned_at: Time.current)
      control.update!(active_maintenance_run: nil)
      run
    end
  end

  # Caller owns the singleton lock, before actor/run/Pool/Node locks. A malformed
  # pointer is never equivalent to absence of a reservation.
  def self.active_maintenance!(control)
    return if control.active_maintenance_run_id.nil?

    run = StorageMaintenanceRun.lock.find_by(id: control.active_maintenance_run_id)
    raise MaintenanceConflict, 'maintenance owner is missing' unless run

    run.supported!
    unless run.state == 'reserved' && run.freeze_epoch == control.epoch
      raise MaintenanceConflict, 'maintenance owner is inconsistent'
    end

    run
  end
  private_class_method :active_maintenance!

  def self.validate_maintenance_control!(control, expected_epoch)
    raise StaleEpoch, 'storage freeze epoch changed' unless control.epoch == expected_epoch
    raise MaintenanceConflict, 'maintenance reservation requires read-only mode' unless control.read_only?
  end
  private_class_method :validate_maintenance_control!

  def self.locked_maintenance_scope!(ids)
    # FOR UPDATE is a current read even under the ordinary REPEATABLE READ
    # isolation. Recheck the entire requested set, then its Nodes, in ID order.
    pools = Pool.where(id: ids).order(:id).lock.to_a
    raise MaintenanceConflict, 'requested storage pools changed' unless pools.map(&:id) == ids

    node_ids = pools.map(&:node_id).uniq.sort
    nodes = Node.where(id: node_ids).order(:id).lock.to_a
    raise MaintenanceConflict, 'requested storage nodes changed' unless nodes.map(&:id) == node_ids

    by_id = nodes.index_by(&:id)
    claims = pools.map do |pool|
      node = by_id.fetch(pool.node_id)
      {
        pool_id: pool.id, node_id: node.id, pool_role: pool.role, filesystem: pool.filesystem,
        node_role: node.role, hypervisor_type: node.hypervisor_type,
        zpool_guid: pool.zpool_guid&.to_i&.to_s
      }
    end
    json = JSON.generate(pools: claims)
    raise ArgumentError, 'requested storage scope is too large' if json.bytesize > StorageMaintenanceRun::SCOPE_LIMIT

    json
  end
  private_class_method :locked_maintenance_scope!

  def self.change_mode!(read_only:, expected_epoch:, reason:)
    raise ArgumentError, 'invalid target mode' unless [true, false].include?(read_only)

    validate_reason!(reason)
    validate_epoch!(expected_epoch, required: true)

    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      target_mode = read_only ? 'read_only' : 'read_write'
      raise StaleEpoch, 'storage freeze epoch changed' if expected_epoch && control.epoch != expected_epoch
      if !read_only && !control.active_maintenance_run_id.nil?
        raise MaintenanceConflict, 'storage maintenance is reserved'
      end
      raise SameMode, "storage is already #{target_mode}" if control.mode == target_mode

      actor = yield
      prior_mode = control.mode
      prior_epoch = control.epoch
      now = Time.current
      control.update!(
        mode: target_mode,
        epoch: prior_epoch + 1,
        requested_by_user_id: actor.fetch(:requested_by_user_id),
        requested_at: now,
        reason: reason.strip
      )
      StorageFreezeTransition.create!(
        storage_freeze_control: control,
        prior_mode:,
        new_mode: target_mode,
        prior_epoch:,
        new_epoch: control.epoch,
        actor_user_id: actor[:actor_user_id],
        actor_user_session_id: actor[:actor_user_session_id],
        actor_user_login: actor[:actor_user_login],
        reason: reason.strip,
        created_at: now
      )
      control
    end
  end
  private_class_method :change_mode!

  def self.validate_reason!(reason)
    raise ArgumentError, 'reason is required' unless reason.is_a?(String) && !reason.strip.empty?
    raise ArgumentError, 'reason is too long' if reason.length > 255
    raise ArgumentError, 'reason contains a control character' if reason.match?(/[[:cntrl:]]/)
  end
  private_class_method :validate_reason!

  def self.validate_epoch!(expected_epoch, required:)
    raise ArgumentError, 'expected epoch is required' if required && expected_epoch.nil?
    return if expected_epoch.nil? || (expected_epoch.is_a?(Integer) && expected_epoch >= 0)

    raise ArgumentError, 'invalid expected epoch'
  end
  private_class_method :validate_epoch!

  def self.locked_api_actor!(user:, user_session:)
    unless user.is_a?(User) && user.persisted? &&
           user_session.is_a?(UserSession) && user_session.persisted?
      raise AuthorizationRefused, 'direct administrator session required'
    end

    actor = User.lock.find_by(id: user.id)
    session = UserSession.lock.find_by(id: user_session.id)
    requested_state = actor&.current_object_state&.state
    active = actor && actor.object_state == 'active' &&
             (requested_state.nil? || requested_state == 'active')
    unless active && actor.role == :admin && session && session.user_id == actor.id &&
           session.admin_id.nil? && session.closed_at.nil?
      raise AuthorizationRefused, 'active direct administrator session required'
    end

    [actor, session]
  end
  private_class_method :locked_api_actor!

  def self.check!
    unless StorageFreezeControl.connection.transaction_open?
      raise 'storage mutation admission requires a staging transaction'
    end

    control = StorageFreezeControl.lock.find(1)
    return control if control.read_write? && control.active_maintenance_run_id.nil?

    raise VpsAdmin::API::Exceptions::StorageReadOnly
  end
end
