module NodeCtld
  class Commands::Node::StorePublicKeys < Commands::Base
    handle 6

    def exec
      db = Db.new

      db.transaction do |t|
        get_pubkeys.each do |type, key|
          t.prepared(
              'INSERT INTO node_pubkeys (node_id, `key_type`, `key`) VALUES (?, ?, ?)
               ON DUPLICATE KEY UPDATE `key` = ?',
              $CFG.get(:vpsadmin, :node_id), type, key, key
          )
        end
      end

      db.close

      ok
    end

    def rollback
      db = Db.new
      db.prepared(
          'DELETE FROM node_pubkeys WHERE node_id = ?',
          $CFG.get(:vpsadmin, :node_id)
      )
      db.close
      ok
    end

    protected
    def get_pubkeys
      ret = {}

      $CFG.get(:node, :pubkey, :types).each do |t|
        ret[t] = File.open($CFG.get(:node, :pubkey, :path).gsub(/%\{type\}/, t)).read.strip
      end

      ret
    end
  end
end
