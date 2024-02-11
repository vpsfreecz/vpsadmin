module Transactions::Vps
  class Autostart < ::Transaction
    t_name :vps_autostart
    t_type 2028
    queue :vps

    def params(vps, enable: nil, priority: nil, revert: true)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        new: {
          enable: enable.nil? ? vps.autostart_enable : enable,
          priority: priority || vps.autostart_priority
        },
        original: {
          enable: vps.autostart_enable,
          priority: vps.autostart_priority
        },
        revert:
      }
    end
  end
end
