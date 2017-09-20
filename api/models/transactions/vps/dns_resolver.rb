module Transactions::Vps
  class DnsResolver < ::Transaction
    t_name :vps_dns_resolver
    t_type 2005
    queue :vps

    def params(vps, orig, resolver)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          nameserver: resolver.addr.split(','),
          original: orig.addr.split(',')
      }
    end
  end
end
