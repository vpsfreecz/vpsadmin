module Transactions::Vps
  class CreateConfig < ::Transaction
    t_name :vps_create_config
    t_type 4003

    def params(vps)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          os_template: vps.os_template.name
      }
    end
  end
end
