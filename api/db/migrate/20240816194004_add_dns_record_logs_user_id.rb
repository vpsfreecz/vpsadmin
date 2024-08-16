class AddDnsRecordLogsUserId < ActiveRecord::Migration[7.1]
  class DnsRecordLog < ActiveRecord::Base
    belongs_to :dns_zone
  end

  class DnsRecord < ActiveRecord::Base
    belongs_to :dns_zone
    belongs_to :host_ip_address
  end

  class DnsZone < ActiveRecord::Base; end

  class HostIpAddress < ActiveRecord::Base
    belongs_to :ip_address
  end

  class IpAddress < ActiveRecord::Base
    belongs_to :network_interface
  end

  class NetworkInterface < ActiveRecord::Base
    belongs_to :vps
  end

  class Vps < ActiveRecord::Base; end

  def change
    add_column :dns_record_logs, :user_id, :bigint, null: true
    add_index :dns_record_logs, :user_id

    reversible do |dir|
      dir.up do
        # Set user_id of existing logs. Since the feature is relatively new,
        # we set it simply to the owner of the zone or, in case of reverse records,
        # to owner of the IP address.

        DnsRecordLog.includes(:dns_zone).all.each do |log|
          dns_record = DnsRecord.find_by(
            dns_zone: log.dns_zone,
            name: log.name,
            record_type: log.record_type
          )

          next if dns_record.nil?

          user_id =
            if dns_record.host_ip_address_id
              ip_address_owner(dns_record.host_ip_address.ip_address)
            else
              log.dns_zone.user_id
            end

          next if user_id.nil?

          log.update!(user_id:)
        end
      end
    end
  end

  protected

  def ip_address_owner(ip)
    ip.user_id || (ip.network_interface_id && ip.network_interface.vps && ip.network_interface.vps.user_id)
  end
end
