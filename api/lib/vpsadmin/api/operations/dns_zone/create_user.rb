require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsZone::CreateUser < Operations::Base
    # @param attrs [Hash]
    # @return [Array(TransactionChain, ::DnsZone)]
    def run(attrs)
      seed_vps = attrs.delete(:seed_vps)
      dns_zone = ::DnsZone.new(**attrs)
      dns_zone.user = ::User.current unless ::User.current.role == :admin

      dns_zone.zone_role =
        if dns_zone.name.end_with?('.in-addr.arpa.') || dns_zone.name.end_with?('.ip6.arpa.')
          'reverse_role'
        else
          'forward_role'
        end

      unless dns_zone.valid?
        raise ActiveRecord::RecordInvalid, dns_zone
      end

      check_collisions!(dns_zone) unless ::User.current.role == :admin

      TransactionChains::DnsZone::CreateUser.fire2(args: [dns_zone], kwargs: { seed_vps: })
    end

    protected

    def check_collisions!(dns_zone)
      zone_segments = dns_zone.name.split('.')

      ::DnsZone.all.each do |existing_zone|
        existing_segments = existing_zone.name.split('.')

        conflict = (is_subdomain?(existing_segments, zone_segments) || is_subdomain?(zone_segments, existing_segments)) \
                   && dns_zone.user_id != existing_zone.user_id
        next unless conflict

        raise Exceptions::OperationError, "#{dns_zone.name.inspect} is already taken"
      end
    end

    def is_subdomain?(parent_segments, child_segments)
      return false if child_segments.length <= parent_segments.length

      child_segments.last(parent_segments.length) == parent_segments
    end
  end
end
