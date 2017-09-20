module Transactions::Vps
  class Mounts < ::Transaction
    t_name :vps_mounts
    t_type 5301

    include Transactions::Utils::Mounts

    def params(vps, mounts)
      self.vps_id = vps.id
      self.node_id = vps.node_id

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
