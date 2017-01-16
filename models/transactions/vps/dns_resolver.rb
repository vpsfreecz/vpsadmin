module Transactions::Vps
  class DnsResolver < ::Transaction
    t_name :vps_dns_resolver
    t_type 2005
    queue :vps

    def params(vps, orig, resolver)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          nameserver: resolver.addr.split(','),
          original: orig.addr.split(',')
      }
    end
  end
end
