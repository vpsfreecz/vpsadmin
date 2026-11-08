class SupersedeLegacyDnsTransferEvents < ActiveRecord::Migration[8.1]
  class Event < ActiveRecord::Base
    self.table_name = 'monitored_events'
  end

  class State < ActiveRecord::Base
    self.table_name = 'monitored_event_states'
  end

  class Observation < ActiveRecord::Base
    self.table_name = 'monitored_event_logs'
    serialize :value
  end

  def up
    Event.where(monitor_name: 'dns_secondary_transfer_failure', class_name: 'DnsServerZone',
                state: [0, 1, 3, 4]).find_each do |event|
      Event.transaction do
        event.lock!
        next unless [0, 1, 3, 4].include?(event.state)

        now = Time.current
        event.update_columns(state: 5, updated_at: now)
        State.create!(monitored_event_id: event.id, state: 5, created_at: now)
        Observation.create!(
          monitored_event_id: event.id, passed: false, created_at: now,
          value: {
            'reason' => 'superseded_by_primary_readiness',
            'replacement_monitor' => 'dns_primary_transfer_failure'
          }
        )
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'retain supersession audit; restoring an obsolete alert is not a rollback'
  end
end
