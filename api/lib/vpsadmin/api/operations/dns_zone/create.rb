require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::Create < Operations::Base
    # @param attrs [Hash]
    # @return [::DnsZone]
    def run(attrs)
      dns_zone = ::DnsZone.new(**attrs)

      ActiveRecord::Base.transaction do
        dns_zone.save!

        ::Network.all.each do |net|
          next if !net.include?(dns_zone) && !dns_zone.include?(net)

          net.ip_addresses.each do |ip|
            next unless dns_zone.include?(ip)

            ip.update!(reverse_dns_zone: dns_zone)
          end
        end
      end

      dns_zone
    end
  end
end
