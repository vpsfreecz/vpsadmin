module Transactions::Vps
  class Mounts < ::Transaction
    t_name :vps_mounts
    t_type 5301

    include Transactions::Utils::Mounts

    def params(vps, mounts)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      res = []

      mounts.each do |mnt|
        res << mount_params(mnt)
      end

      {
          mounts: res
      }
    end
  end
end
