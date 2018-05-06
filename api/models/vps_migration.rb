class VpsMigration < ActiveRecord::Base
  belongs_to :vps
  belongs_to :migration_plan
  belongs_to :transaction_chain
  belongs_to :src_node, class_name: 'Node'
  belongs_to :dst_node, class_name: 'Node'
  belongs_to :user

  enum state: %i(queued running cancelled done error)

  validate :check_uniqueness

  def check_uniqueness
    return if persisted?

    exists = self.class.joins(:migration_plan).where(
      vps: vps,
      state: [
        self.class.states[:queued],
        self.class.states[:running],
      ],
      migration_plans: {
        state: [
          ::VpsMigration.states[:staged],
          ::VpsMigration.states[:running],
          ::VpsMigration.states[:cancelling],
          ::VpsMigration.states[:failing],
        ]
      }
    ).any?

    if exists
      errors.add(:vps, 'is already in a migration plan')
    end
  end
end
