module Transactions::Vps
  class WaitForRoutes < ::Transaction
    t_name :vps_wait_for_routes
    t_type 2026
    queue :vps

    # @param vps [::Vps]
    # @param timeout [Integer, nil]
    def params(vps, timeout: nil)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        timeout: timeout,
      }
    end
  end
end
