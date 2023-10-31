module NodeCtld
  class Export
    include OsCtl::Lib::Utils::Log
    include Utils::System

    def self.init
      ex = new
      ex.init
    end

    def init
      tp = ThreadPool.new($CFG.get(:exports, :parallel_start))
      cache = list_existing_servers

      RpcClient.run do |rpc|
        rpc.each_export do |ex|
          tp.add { init_export(ex, cache) }
        end
      end

      tp.run
    end

    def init_export(export, cache)
      srv = NfsServer.new(export['id'], export['ip_address'])

      if cache.has_key?(srv.name)
        log(:info, "Found NFS server #{export['id']}")
      else
        log(:info, "Creating NFS server #{export['id']}")
        srv.create!(threads: export['threads'])

        export['hosts'].each do |host|
          opts = build_options(host)

          if export['clone_name']
            srv.add_snapshot_export(
              export['pool_fs'],
              export['clone_name'],
              export['path'],
              "#{host['ip_address']}/#{host['prefix']}",
              opts,
            )
          else
            srv.add_filesystem_export(
              export['pool_fs'],
              export['dataset_name'],
              export['path'],
              "#{host['ip_address']}/#{host['prefix']}",
              opts,
            )
          end
        end
      end

      if export['enabled'] && !cache[srv.name]
        log(:info, "Starting NFS server #{export['id']}")
        srv.start!
        sleep($CFG.get(:exports, :start_delay))
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
        ret[v] = export[v]
      end

      ret
    end
  end
end
