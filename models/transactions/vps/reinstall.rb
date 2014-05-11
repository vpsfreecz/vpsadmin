module Transactions::Vps
  class Reinstall < ::Transaction
    t_name :vps_reinstall
    t_type 3003

    def prepare(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          hostname: vps.hostname,
          template: vps.os_template.name,
          onboot: vps.node.location.location_vps_onboot,
          nameserver: vps.dns_resolver.addr,
          ip_addrs: vps.ip_addresses.all.map { |ip| ip.addr }
      }
    end
  end
end
