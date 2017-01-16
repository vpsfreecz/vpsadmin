module Transactions::Vps
  class Resources < ::Transaction
    t_name :vps_resources
    t_type 2003
    queue :vps

    def params(vps, resources)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          resources: resources.map { |r|
            {
                resource: r.user_cluster_resource.cluster_resource.name,
                value: r.value,
                original: r.value_was
            }
          }
      }
    end
  end
end
