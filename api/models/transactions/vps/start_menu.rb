module Transactions::Vps
  class StartMenu < ::Transaction
    t_name :vps_start_menu
    t_type 2030
    queue :vps

    def params(vps, original_timeout)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        new_timeout: vps.start_menu_timeout,
        original_timeout: original_timeout,
      }
    end
  end
end
