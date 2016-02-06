class MigrationPlan < ActiveRecord::Base
  belongs_to :user
  belongs_to :node
  has_many :vps_migrations
  has_many :resource_locks, as: :locked_by, dependent: :destroy

  enum state: %i(staged running cancelling failing cancelled done error)

  def fail!
    update!(state: self.class.states[:failing])
  end

  # @params state [Symbol]
  def finish!(new_state = nil)
    unless new_state
      case self.state
      when 'running'
        new_state = :done

      when 'cancelling'
        new_state = :cancelled

      when 'failing'
        new_state = :error
      end
    end

    update!(
        state: self.class.states[new_state],
        finished_at: Time.now,
    )

    resource_locks.delete_all
  end
end
