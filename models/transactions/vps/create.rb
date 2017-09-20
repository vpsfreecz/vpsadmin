module Transactions::Vps
  class Create < ::Transaction
    t_name :vps_create
    t_type 3001
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          hostname: vps.hostname,
          template: vps.os_template.name,
          onboot: vps.node.location.vps_onboot,
      }
    end
  end
end
