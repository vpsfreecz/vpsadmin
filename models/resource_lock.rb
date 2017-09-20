# Used to lock a resource to ensure that only one transaction chain
# may be working with the resource. The resource is represented
# by its class name and row id. To make a model lockable, include
# module Lockable.
class ResourceLock < ActiveRecord::Base
  belongs_to :transaction_chain
  belongs_to :locked_by, polymorphic: true

  # Assign the lock to +chain+.
  def assign_to(obj)
    update(locked_by: obj)
  end

  # Remove the lock.
  def release
    destroy
  end

  # True if this lock locks +obj+.
  def locks?(obj)
    resource == obj.lock_resource_name && row_id == obj.id
  end
end
