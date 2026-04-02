module Transactions::Pool
  class RevokeRsyncKey < ::Transaction
    t_name :pool_revoke_rsync_key
    t_type 5264

    def params(host_pool, key_pool)
      raise "no pubkey set for pool #{key_pool.id}" unless key_pool.migration_public_key

      self.node_id = host_pool.node_id
      { pubkey: key_pool.migration_public_key }
    end
  end
end
