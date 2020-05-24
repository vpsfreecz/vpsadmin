module Transactions::Vps
  class RecoverCleanup < ::Transaction
    t_name :vps_recover_cleanup
    t_type 3303
    queue :vps

    def params(vps, opts)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        cgroups: opts[:cgroups] ? true : false,
        network_interfaces: opts[:network_interfaces] ? true : false,
      }
    end
  end
end
