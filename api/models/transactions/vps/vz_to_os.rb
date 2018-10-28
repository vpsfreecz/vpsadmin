module Transactions::Vps
  class VzToOs < ::Transaction
    t_name :vps_vztoos
    t_type 2024
    queue :vps

    # @param vps [::Vps]
    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        distribution: vps.os_template.distribution,
        version: vps.os_template.version,
      }
    end
  end
end
