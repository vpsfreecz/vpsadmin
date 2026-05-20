module Transactions::Pool
  class GenerateSendKey < ::Transaction
    t_name :pool_generate_send_key
    t_type 5261

    def params(pool, pool_ids: [pool.id])
      self.node_id = pool.node_id
      {
        pool_id: pool.id,
        pool_ids:,
        pool_name: pool.name,
        pool_fs: pool.filesystem
      }
    end
  end
end
