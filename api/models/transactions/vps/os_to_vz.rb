module Transactions::Vps
  class OsToVz < ::Transaction
    t_name :vps_ostovz
    t_type 2025
    queue :vps

    # @param vps [::Vps]
    # @Param os_template [::OsTemplate]
    def params(vps, os_template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        distribution: os_template.distribution,
        version: os_template.version,
      }
    end
  end
end
