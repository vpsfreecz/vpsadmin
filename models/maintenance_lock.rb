class MaintenanceLock < ActiveRecord::Base
  belongs_to :user

  def lock!(obj)
    self.class.transaction do
      tmp = self.class.find_by(
          class_name: class_name,
          row_id: row_id,
          active: true
      )

      return false if tmp

      self.active = true
      save!

      # Lock self and all children objects.
      obj.update!(
          maintenance_lock: maintain_lock(:lock),
          maintenance_lock_reason: self.reason
      ) if obj && obj.respond_to?(:update!)

      lock_children(obj || ::Object.const_get(self.class_name).new)
      true
    end
  end

  def lock_children(parent)
    children = parent.class.maintenance_children
    return unless children

    children.each do |child|
        obj.update!(
            maintenance_lock: maintain_lock(:master_lock),
            maintenance_lock_reason: self.reason
        )

        lock_children(obj)
    end
  end

  def unlock!(obj)
    self.class.transaction do
      self.active = false
      save!

      # Unlock all children objects that are otherwise
      # not locked.
      obj.update!(
          maintenance_lock: maintain_lock(:no),
          maintenance_lock_reason: nil
      ) if obj && obj.respond_to?(:update!)

      unlock_children(obj || Object.const_get(self.class_name).new)
      true
    end
  end

  def unlock_children(parent)
    children = parent.class.maintenance_children
    return unless children

    children.each do |child|
      parent.method(child).call.all.each do |obj|
        next if obj.find_maintenance_lock

        obj.update!(
            maintenance_lock: maintain_lock(:no),
            maintenance_lock_reason: nil
        )

        unlock_children(obj)
      end
    end
  end

  def maintain_lock(*args)
    self.class.maintain_lock(*args)
  end

  def self.maintain_lock(k)
    opts = %i(no lock master_lock)

    if k.is_a?(::Symbol)
      opts.index(k)
    else
      opts[k]
    end
  end
end
