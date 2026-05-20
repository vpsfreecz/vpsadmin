module NodeCtld
  class Commands::Pool::GenerateSendKey < Commands::Base
    handle 5261
    needs :system, :osctl

    def exec
      osctl_pool(@pool_name, %i[send key gen], [], { force: true })

      pubkey, privkey = get_key_paths

      content = File.read(pubkey).strip

      db = Db.new
      pool_ids = migration_key_pool_ids
      db.prepared(
        "UPDATE pools SET migration_public_key = ? WHERE id IN (#{pool_ids.map { '?' }.join(',')})",
        content,
        *pool_ids
      )
      db.close

      ok
    end

    def rollback
      get_key_paths.each do |file|
        File.unlink(file)
      rescue Errno::ENOENT
        next
      end

      db = Db.new
      pool_ids = migration_key_pool_ids
      db.prepared(
        "UPDATE pools SET migration_public_key = NULL WHERE id IN (#{pool_ids.map { '?' }.join(',')})",
        *pool_ids
      )
      db.close

      ok
    end

    protected

    def migration_key_pool_ids
      (@pool_ids || [@pool_id]).map(&:to_i)
    end

    def get_key_paths
      [
        osctl_pool(@pool_name, %i[send key path public]).output.strip,
        osctl_pool(@pool_name, %i[send key path private]).output.strip
      ]
    end
  end
end
