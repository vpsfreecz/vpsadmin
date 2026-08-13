class RemoveLegacyDnsSecondaryTransferFailureEvents < ActiveRecord::Migration[8.1]
  class MonitoredEvent < ActiveRecord::Base
    self.table_name = 'monitored_events'
  end

  class MonitoredEventState < ActiveRecord::Base
    self.table_name = 'monitored_event_states'
  end

  class MonitoredEventLog < ActiveRecord::Base
    self.table_name = 'monitored_event_logs'
  end

  def up
    MonitoredEvent
      .where(
        monitor_name: 'dns_secondary_transfer_failure',
        class_name: 'DnsServerZone'
      )
      .in_batches do |events|
        ids = events.pluck(:id)
        MonitoredEventState.where(monitored_event_id: ids).delete_all
        MonitoredEventLog.where(monitored_event_id: ids).delete_all
        MonitoredEvent.where(id: ids).delete_all
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'legacy DNS secondary transfer monitoring events cannot be reconstructed'
  end
end
