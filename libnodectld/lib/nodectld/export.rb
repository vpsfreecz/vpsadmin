module NodeCtld
  class Export
    include OsCtl::Lib::Utils::Log
    include Utils::System

    def self.init(db)
      ex = new
      ex.init(db)
    end

    def init(db)
      tp = ThreadPool.new(8)
      cache = list_existing_servers

      db.prepared('
        SELECT
          p.filesystem AS pool_fs, ds.full_name AS dataset, cl.name AS clone_name,
          ex.*
        FROM exports ex
        INNER JOIN dataset_in_pools dips ON dips.id = ex.dataset_in_pool_id
        INNER JOIN datasets ds ON ds.id = dips.dataset_id
        LEFT JOIN snapshot_in_pool_clones cl ON cl.id = ex.snapshot_in_pool_clone_id
        INNER JOIN pools p ON p.id = dips.pool_id
        WHERE p.node_id = ?
      ', $CFG.get(:vpsadmin, :node_id)).each do |ex|
        tp.add { init_export(ex, cache) }
      end

      tp.run
    end

    def init_export(export, cache)
      db = Db.new

      ip_addr = db.prepared('
        SELECT ips.ip_addr
        FROM network_interfaces netifs
        INNER JOIN ip_addresses ips ON ips.network_interface_id = netifs.id
        WHERE netifs.export_id = ?
        LIMIT 1
      ', export['id']).get['ip_addr']
      puts ip_addr

      srv = NfsServer.new(export['id'], ip_addr)

      if cache.has_key?(srv.name)
        log(:info, "Found NFS server #{export['id']}")
      else
        log(:info, "Creating NFS server #{export['id']}")
        srv.create!

        opts = build_options(export)

        db.prepared('
          SELECT ips.ip_addr, ips.prefix
          FROM export_hosts eh
          INNER JOIN ip_addresses ips ON ips.id = eh.ip_address_id
          WHERE export_id = ?
        ', export['id']).each do |host|
          if export['clone_name']
            srv.add_snapshot_export(
              export['pool_fs'],
              export['snapshot_clone'],
              export['path'],
              "#{host['ip_addr']}/#{host['prefix']}",
              opts,
            )
          else
            srv.add_filesystem_export(
              export['pool_fs'],
              export['dataset'],
              export['path'],
              "#{host['ip_addr']}/#{host['prefix']}",
              opts,
            )
          end
        end
      end

      if export['enabled'] && !cache[srv.name]
        log(:info, "Starting NFS server #{export['id']}")
        srv.start!
      end
    end

    protected
    def list_existing_servers
      ret = {}
      str = syscmd('osctl-exportfs server ls -H -o server,state').output

      str.split("\n").each do |line|
        server, state = line.split
        ret[server] = state == 'running'
      end

      ret
    end

    def build_options(export)
      ret = {}
      keys = %w(rw sync subtree_check root_squash)

      keys.each do |v|
        ret[v] = export[v] == 1
      end

      ret
    end
  end
end
