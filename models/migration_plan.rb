class MigrationPlan < ActiveRecord::Base
  belongs_to :user
  belongs_to :node
  has_many :vps_migrations
  has_many :resource_locks, as: :locked_by, dependent: :destroy

  enum state: %i(staged running cancelling cancelled done error)

  attr_accessor :skipped_vps

  def initialize(*args)
    @skipped_vps = 0
    super(*args)
  end

  # @params state [Symbol]
  def finish!(state)
    update!(
        state: self.class.states[state],
        finished_at: Time.now,
    )

    resource_locks.delete_all
  end
end
