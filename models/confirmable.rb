module Confirmable
  CONFIRM_STATES = %i(confirm_create confirmed confirm_destroy)

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def confirmed(v)
      v.is_a?(Integer) ? CONFIRM_STATES[v] : CONFIRM_STATES.index(v)
    end
  end

  def confirmed
    CONFIRM_STATES[ read_attribute(:confirmed) ]
  end

  def confirmed=(v)
    write_attribute(:confirmed, v.is_a?(Integer) ? v : CONFIRM_STATES.index(v))
  end

  def confirmed?
    confirmed == :confirmed
  end
end
