module Transactions::Vps
  class UnmanageDnsResolver < ::Transaction
    t_name :vps_unmanage_dns_resolver
    t_type 2027
    queue :vps

    def params(vps, orig)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        original: orig.addr.split(',')
      }
    end
  end
end
