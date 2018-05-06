module Transactions::Vps
  class Mount < ::Transaction
    t_name :vps_mount
    t_type 5302

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
