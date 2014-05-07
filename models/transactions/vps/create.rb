module Transactions::Vps
  class Create < ::Transaction
    t_name :vps_create
    t_type 3001

    def prepare(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          hostname: vps.hostname,
          template: vps.os_template.name,
          onboot: vps.location.location_vps_onboot,
          nameserver: '8.8.8.8', # fixme
      }
    end
  end
end
