class AddDnsZoneConfirmable < ActiveRecord::Migration[7.1]
  class DnsZone < ActiveRecord::Base; end
  class DnsServerZone < ActiveRecord::Base; end
  class DnsZoneTransfer < ActiveRecord::Base; end

  def change
    add_column :dns_zones, :confirmed, :integer, null: false, default: 0
    add_column :dns_server_zones, :confirmed, :integer, null: false, default: 0
    add_column :dns_zone_transfers, :confirmed, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        [DnsZone, DnsServerZone, DnsZoneTransfer].each do |klass|
          klass.all.update_all(confirmed: 1)
        end
      end
    end
  end
end
