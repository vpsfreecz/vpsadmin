require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::CreateSystem < Operations::Base
    # @param attrs [Hash]
    # @return [Array(nil, ::DnsZone)]
    def run(attrs)
      dns_zone = ::DnsZone.new(**attrs)

      ActiveRecord::Base.transaction do
        dns_zone.save!

        next if dns_zone.forward_role?

        ::Network.all.each do |net|
          next if !net.include?(dns_zone) && !dns_zone.include?(net)

          net.ip_addresses.each do |ip|
            next unless dns_zone.include?(ip)

            # In case the networks overlap, prefer more specific prefix
            next if ip.reverse_dns_zone && ip.reverse_dns_zone.reverse_network_prefix > dns_zone.reverse_network_prefix

            ip.update!(reverse_dns_zone: dns_zone)
          end
        end
      end

      [nil, dns_zone]
    end
  end
end
