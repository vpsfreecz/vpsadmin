module Transactions::Vps
  class CgroupVersion < ::Transaction
    t_name :vps_cgroup_version
    t_type 2039
    queue :vps

    def params(vps, new_version, original_version)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        new_version:,
        original_version:
      }
    end
  end
end
