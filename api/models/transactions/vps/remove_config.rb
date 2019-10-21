module Transactions::Vps
  class RemoveConfig < ::Transaction
    t_name :vps_remove_config
    t_type 4006
    queue :vps

    # @param vps [::Vps]
    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        pool_fs: vps.dataset_in_pool.pool.filesystem,
      }
    end
  end
end
