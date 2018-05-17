# Raised when attempting the lock an already locked resource.
class ResourceLocked < StandardError

end

# Include this module to make a model lockable.
module Lockable
  # Lock the resource. The lock is assigned to +chain+ if provided.
  #
  # By default, this method does not wait if the resource is already
  # locked, but raises ResourceLocked. This may be changed with
  # named arguments +block+ and +timeout+.
  #
  # When given a block, it is executed after the resource is locked
  # and the lock is released when the block finishes.
  def acquire_lock(lock_by = nil, block: false, timeout: 300, &code_block)
    start = Time.now

    begin
      lock = ResourceLock.create!(
        resource: lock_resource_name,
        row_id: self.id,
        locked_by: lock_by,
      )

      if code_block
        begin
          code_block.call(lock)

        rescue
          raise

        ensure
          lock.release
        end
      end

      return lock

    rescue ActiveRecord::RecordNotUnique => e
      if block
        raise ResourceLocked.new(e.message) if start + timeout < Time.now

        sleep(5)
        retry

      else
        raise ResourceLocked.new(e.message)
      end
    end
  end

  # Assign already acquired lock to +chain+.
  def assign_lock(obj)
    ResourceLock.find_by(
      resource: lock_resource_name,
      row_id: self.id,
      locked_by: nil,
    ).assign_to(obj)
  end

  # Release lock owned by +chain+.
  def release_lock(locked_by = nil)
    ResourceLock.find_by(
      resource: lock_resource_name,
      row_id: self.id,
      locked_by: locked_by,
    ).release
  end

  # True if this resource is locked.
  def locked?
    !ResourceLock.find_by(
      resource: lock_resource_name,
      row_id: self.id,
    ).nil?
  end

  # Returns the class name, which is used as a resource name.
  def lock_resource_name
    self.class.name
  end
end
