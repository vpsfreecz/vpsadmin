class RemoveUpToDateDnsTransferFailures < ActiveRecord::Migration[8.1]
  class DnsServerZone < ActiveRecord::Base
    self.table_name = 'dns_server_zones'

    has_many :dns_server_zone_transfer_logs,
             class_name: 'RemoveUpToDateDnsTransferFailures::DnsServerZoneTransferLog',
             foreign_key: :dns_server_zone_id
  end

  class DnsServerZoneTransferLog < ActiveRecord::Base
    self.table_name = 'dns_server_zone_transfer_logs'

    belongs_to :dns_server_zone,
               class_name: 'RemoveUpToDateDnsTransferFailures::DnsServerZone'

    scope :up_to_date_transfer_failure, lambda {
      where(
        status: 1,
        reason_code: 'unknown',
        reason: 'The transfer failed',
        serial: nil
      ).where(
        'LOWER(message) = ?', 'up to date'
      ).where(
        'LOWER(raw_message) LIKE ?', "%transfer of '%/in' from %#%: transfer status: up to date"
      )
    }
  end

  def up
    DnsServerZone.reset_column_information
    DnsServerZoneTransferLog.reset_column_information

    ActiveRecord::Base.transaction do
      repair_latest_transfer_fields
      DnsServerZoneTransferLog.up_to_date_transfer_failure.delete_all
    end
  end

  def down
    # Deleted synthetic failure logs cannot be reconstructed.
  end

  private

  def repair_latest_transfer_fields
    DnsServerZone
      .where(last_transfer_log_id: DnsServerZoneTransferLog.up_to_date_transfer_failure.select(:id))
      .find_each do |server_zone|
        repair_latest_transfer_fields_for(server_zone)
      end
  end

  def repair_latest_transfer_fields_for(server_zone)
    replacement =
      server_zone
      .dns_server_zone_transfer_logs
      .where.not(id: DnsServerZoneTransferLog.up_to_date_transfer_failure.select(:id))
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
