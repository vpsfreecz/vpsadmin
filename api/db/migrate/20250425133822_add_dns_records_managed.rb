class AddDnsRecordsManaged < ActiveRecord::Migration[7.2]
  class DnsZone < ActiveRecord::Base
    has_many :dns_records

    enum :zone_role, %i[forward_role reverse_role]
    enum :zone_source, %i[internal_source external_source]
  end

  class DnsRecord < ActiveRecord::Base
    belongs_to :dns_zone
  end

  def change
    add_column :dns_records, :managed, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        DnsRecord.all.includes(:dns_zone).each do |r|
          r.managed = r.dns_zone.internal_source? \
                        && r.dns_zone.reverse_role? \
                        && !r.dns_zone.reverse_network_address.nil?
          r.save!
        end
      end
    end
  end
end
