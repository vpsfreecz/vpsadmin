class MakeDnsRecordLogsStandalone < ActiveRecord::Migration[7.1]
  class DnsRecordLog < ActiveRecord::Base
    belongs_to :dns_zone
  end

  class DnsZone < ActiveRecord::Base
    has_many :dns_record_logs
  end

  def change
    add_column :dns_record_logs, :dns_zone_name, :string, limit: 500, null: true

    reversible do |dir|
      dir.up do
        DnsRecordLog.includes(:dns_zone).all.each do |log|
          log.update!(dns_zone_name: log.dns_zone.name)
        end
      end
    end

    change_column_null :dns_record_logs, :dns_zone_name, false

    add_column :dns_record_logs, :transaction_chain_id, :bigint, null: true
    change_column_null :dns_record_logs, :dns_zone_id, true
  end
end
