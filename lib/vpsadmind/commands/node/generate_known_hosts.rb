module VpsAdmind
  class Commands::Node::GenerateKnownHosts < Commands::Base
    handle 5
    needs :system
    
    def exec
      p = $CFG.get(:node, :known_hosts)

      # Backup current known_hosts for rollback
      syscmd("#{$CFG.get(:bin, :cp)} #{p} #{p}.backup") if File.exists?(p)

      # Write new hosts
      db = Db.new
      f = File.open(p, "w")

      rs = db.query(
        'SELECT node_id, `key`, n.ip_addr
           FROM nodes n
           INNER JOIN node_pubkey p ON n.id = p.node_id
           ORDER BY node_id, `type`'
      )

      rs.each_hash do |r|
        f.write("#{r["server_ip4"]} #{r["key"]}\n")
      end

      f.close
      db.close

      ok
    end

    def rollback
      new = $CFG.get(:node, :known_hosts)
      backup = $CFG.get(:node, :known_hosts) + '.backup'

      if File.exists?(backup)
        syscmd("#{$CFG.get(:bin, :mv)} #{backup} #{new}")

      elsif File.exists?(new)
        File.delete(new)
      end

      ok
    end
  end
end
