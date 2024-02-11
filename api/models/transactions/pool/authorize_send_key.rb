module Transactions::Pool
  class AuthorizeSendKey < ::Transaction
    t_name :pool_authorize_send_key
    t_type 5262

    def params(dst_pool, src_pool, ctid, name, passphrase)
      raise "no pubkey set for pool #{src_pool.id}" unless src_pool.migration_public_key

      self.node_id = dst_pool.node_id
      {
        pool_name: dst_pool.name,
        pool_fs: dst_pool.filesystem,
        pubkey: src_pool.migration_public_key,
        name:,
        ctid: ctid.to_s,
        passphrase:
      }
    end
  end
end
