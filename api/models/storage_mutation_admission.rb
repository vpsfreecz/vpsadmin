require 'securerandom'

# The freeze row serializes new storage writers with a switch to read_only.
# Call while staging a chain, in the same SQL transaction as its writes.
class StorageMutationAdmission
  class StaleEpoch < StandardError; end
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

  def self.change_mode!(read_only:, expected_epoch:, reason:)
    raise ArgumentError, 'invalid target mode' unless [true, false].include?(read_only)

    validate_reason!(reason)
    validate_epoch!(expected_epoch, required: true)

    StorageFreezeControl.transaction(requires_new: true) do
      control = StorageFreezeControl.lock.find(1)
      target_mode = read_only ? 'read_only' : 'read_write'
      raise StaleEpoch, 'storage freeze epoch changed' if expected_epoch && control.epoch != expected_epoch
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
    raise ArgumentError, 'reason is required' if reason.to_s.strip.empty?
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
    return control if control.read_write?

    raise VpsAdmin::API::Exceptions::StorageReadOnly
  end
end
