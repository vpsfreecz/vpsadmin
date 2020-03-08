module NodeCtld
  class Commands::Node::GenerateSendKey < Commands::Base
    handle 5261
    needs :system, :osctl

    def exec
      osctl(%i(send key gen), [], {force: true}, {pool: pool_name})

      pubkey, privkey = get_key_paths

      content = File.read(pubkey).strip

      db = Db.new
      db.prepared(
        'UPDATE pools SET migration_public_key = ? WHERE id = ?',
        content,
        @pool_id,
      )
      db.close

      ok
    end

    def rollback
      get_key_paths.each do |file|
        begin
          File.unlink(file)
        rescue Errno::ENOENT
          next
        end
      end

      db = Db.new
      db.prepared(
        'UPDATE pools SET migration_public_key = NULL WHERE id = ?',
        @pool_id
      )
      db.close

      ok
    end

    protected
    def pool_name
      @pool_name ||= @pool_fs.split('/').first
    end

    def get_key_paths
      [
        osctl(%i(send key path public), [], {}, {pool: pool_name}).output.strip,
        osctl(%i(send key path private), [], {}, {pool: pool_name}).output.strip,
      ]
    end
  end
end
