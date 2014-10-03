module Transactions::Vps
  class DnsResolver < ::Transaction
    t_name :vps_dns_resolver
    t_type 2005

    def params(vps, resolver)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          nameserver: resolver.addr.split(',')
      }
    end
  end
end
