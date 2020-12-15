module Transactions::Vps
  class Autostart < ::Transaction
    t_name :vps_autostart
    t_type 2028
    queue :vps

    def params(vps, enable: true, revert: true)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        enable: enable,
        revert: revert,
      }
    end
  end
end
