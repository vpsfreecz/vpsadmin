module NodeCtld
  class Commands::Node::AuthorizeSendKeys < Commands::Base
    handle 5262
    needs :system, :osctl

    def exec
      authorized_keys = PoolAuthorizedKeys.new(pool_name)

      fetch_pubkeys.each do |key|
        authorized_keys.authorize(key, reload: false)
      end

      ok
    end

    def rollback
      authorized_keys = PoolAuthorizedKeys.new(pool_name)

      fetch_pubkeys.each do |key|
        authorized_keys.revoke(key)
      end

      ok
    end

    protected
    def pool_name
      @pool_name ||= @pool_fs.split('/').first
    end

    def fetch_pubkeys
      db = Db.new
      ret = []

      db.query(
        "SELECT migration_public_key
        FROM pools
        WHERE
          id IN (#{@authorize_pool_ids.join(',')})
          AND migration_public_key IS NOT NULL"
      ).each do |row|
        ret << row['migration_public_key']
      end

      db.close
      ret
    end
  end
end
