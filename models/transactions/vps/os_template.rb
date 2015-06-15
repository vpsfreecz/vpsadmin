module Transactions::Vps
  class OsTemplate < ::Transaction
    t_name :vps_os_template
    t_type 2013

    def params(vps, orig, os_template)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          os_template: os_template.name,
          original: orig.name
      }
    end
  end
end
