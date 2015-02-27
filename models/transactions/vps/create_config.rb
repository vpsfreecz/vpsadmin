module Transactions::Vps
  class CreateConfig < ::Transaction
    t_name :vps_create_config
    t_type 4003

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {}
    end
  end
end
