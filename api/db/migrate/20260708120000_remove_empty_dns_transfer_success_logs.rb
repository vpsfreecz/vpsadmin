class RemoveEmptyDnsTransferSuccessLogs < ActiveRecord::Migration[8.1]
  class DnsServerZone < ActiveRecord::Base
    self.table_name = 'dns_server_zones'

    has_many :dns_server_zone_transfer_logs,
             class_name: 'RemoveEmptyDnsTransferSuccessLogs::DnsServerZoneTransferLog',
             foreign_key: :dns_server_zone_id
  end

  class DnsServerZoneTransferLog < ActiveRecord::Base
    self.table_name = 'dns_server_zone_transfer_logs'

    belongs_to :dns_server_zone,
               class_name: 'RemoveEmptyDnsTransferSuccessLogs::DnsServerZone'

    scope :empty_transfer_success, lambda {
      where(
        status: 0,
        serial: 0,
        message: 'Transfer completed successfully'
      ).where(
        arel_table[:raw_message].matches(
          '%Transfer completed: 0 messages, 0 records, 0 bytes,%'
        )
      ).where(
        arel_table[:raw_message].matches('%(serial 0)%')
      )
    }
  end

  def up
    DnsServerZone.reset_column_information
    DnsServerZoneTransferLog.reset_column_information

    ActiveRecord::Base.transaction do
      repair_latest_transfer_fields
      DnsServerZoneTransferLog.empty_transfer_success.delete_all
    end
  end

  def down
    # Deleted synthetic success logs cannot be reconstructed.
  end

  private

  def repair_latest_transfer_fields
    DnsServerZone
      .where(last_transfer_log_id: DnsServerZoneTransferLog.empty_transfer_success.select(:id))
      .find_each do |server_zone|
        repair_latest_transfer_fields_for(server_zone)
      end
  end

  def repair_latest_transfer_fields_for(server_zone)
    replacement =
      server_zone
      .dns_server_zone_transfer_logs
      .where.not(id: DnsServerZoneTransferLog.empty_transfer_success.select(:id))
      .order(event_at: :desc, id: :desc)
      .first

    server_zone.update_columns(
      last_transfer_log_id: replacement&.id,
      last_transfer_at: replacement&.event_at,
      last_transfer_status: replacement&.status,
      last_transfer_reason_code: replacement&.status == 1 ? replacement.reason_code : nil,
      last_transfer_reason: replacement&.status == 1 ? replacement.reason : nil,
      last_transfer_primary_addr: replacement&.primary_addr,
      last_transfer_serial: replacement&.serial
    )
  end
end
