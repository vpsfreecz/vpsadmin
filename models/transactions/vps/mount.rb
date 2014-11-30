module Transactions::Vps
  class Mount < ::Transaction
    t_name :vps_mount
    t_type 5302

    def params(vps, mounts)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      res = []

      mounts.each do |mnt|
        if mnt.is_a?(::Mount)
          # FIXME

        elsif mnt.is_a?(::DatasetInPool)
          res << {
              type: :zfs,
              pool_fs: mnt.pool.filesystem,
              dataset: mnt.dataset.full_name
          }

        else
          fail 'invalid mount type'
        end
      end

      {
          mounts: res
      }
    end
  end
end
