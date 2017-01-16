module Transactions::Vps
  class Umount < ::Transaction
    t_name :vps_umount
    t_type 5303

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
