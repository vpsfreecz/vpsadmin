module Transactions::Vps
  class Mounts < ::Transaction
    t_name :vps_mounts
    t_type 5301

    include Transactions::Utils::Mounts

    def params(vps, mounts)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

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
