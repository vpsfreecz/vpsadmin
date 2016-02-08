class MigrationPlan < ActiveRecord::Base
  belongs_to :user
  belongs_to :node
  has_many :vps_migrations
  has_many :resource_locks, as: :locked_by, dependent: :destroy

  enum state: %i(staged running cancelling failing cancelled done error)

  def start!
    self.class.transaction(requires_new: true) do
      i = 0

      vps_migrations.order('created_at').each do |m|
        begin
          chain = TransactionChains::Vps::Migrate.fire2(
              args: [m.vps, m.dst_node, {outage_window: m.outage_window}],
          )
         
          m.update!(
              state: ::VpsMigration.states[:running],
              started_at: Time.now,
              transaction_chain: chain,
          )

          i += 1
          break if i >= concurrency

        rescue ResourceLocked
          next
        end
      end

      update!(state: self.class.states[:running])
    end
  end

  def cancel!
    update!(state: self.class.states[:cancelling])
  end
  
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
