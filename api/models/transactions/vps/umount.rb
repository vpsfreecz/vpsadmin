module Transactions::Vps
  class Umount < ::Transaction
    t_name :vps_umount
    t_type 5303

    include Transactions::Utils::Mounts

    def params(vps, mounts)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      res = []

      mounts.each do |mnt|
        res << mount_params(mnt)
      end

      {
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          mounts: res,
      }
    end
  end
end
