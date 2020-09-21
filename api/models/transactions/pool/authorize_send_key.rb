module Transactions::Pool
  class AuthorizeSendKey < ::Transaction
    t_name :pool_authorize_send_key
    t_type 5262

    def params(dst_pool, src_pool, ctid, name, passphrase)
      unless src_pool.migration_public_key
        fail "no pubkey set for pool #{src_pool.id}"
      end

      self.node_id = dst_pool.node_id
      {
        pool_fs: dst_pool.filesystem,
        pubkey: src_pool.migration_public_key,
        name: name,
        ctid: ctid.to_s,
        passphrase: passphrase,
      }
    end
  end
end
