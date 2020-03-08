module Transactions::Pool
  class AuthorizeSendKeys < ::Transaction
    t_name :pool_authorize_send_keys
    t_type 5262

    def params(pool, other_pools)
      self.node_id = pool.node_id
      {
        pool_id: pool.id,
        pool_fs: pool.filesystem,
        authorize_pool_ids: other_pools.map(&:id),
      }
    end
  end
end
