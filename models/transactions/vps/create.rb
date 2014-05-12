module Transactions::Vps
  class Create < ::Transaction
    t_name :vps_create
    t_type 3001

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          hostname: vps.hostname,
          template: vps.os_template.name,
          onboot: vps.node.location.location_vps_onboot,
          nameserver: vps.dns_resolver.addr
      }
    end
  end
end
