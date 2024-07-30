class AddDnsRecordsConfirmable < ActiveRecord::Migration[7.1]
  class DnsRecord < ActiveRecord::Base; end

  def change
    add_column :dns_records, :confirmed, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        DnsRecord.all.update_all(confirmed: 1)
      end
    end
  end
end
