module Transactions::Vps
  class RescueLeave < ::Transaction
    t_name :vps_rescue_leave
    t_type 2038
    queue :vps
    irreversible

    # @param vps [::Vps]
    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        os_family: vps.os_family.name,
        hostname: vps.manage_hostname ? vps.hostname : nil,
        distribution: vps.os_template.distribution,
        version: vps.os_template.version,
        arch: vps.os_template.arch,
        variant: vps.os_template.variant
      }
    end
  end
end
