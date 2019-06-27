require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Node
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    def self.init(db)
      new.init(db)
    end

    def init(db)
      pools(db).each do |fs|
        wait_for_pool(fs)
      end
    end

    def log_type
      'node'
    end

    protected
    def wait_for_pool(fs)
      name = fs.split('/').first
      sv = "pool-#{name}"

      # Wait for runit service pool-$name to finish
      until File.exist?(File.join('/run/service', sv, 'done'))
        log(:info, "Waiting for service #{sv} to finish")
        sleep(5)
      end

      # Wait for osctld to import the pool, if this node is a hypervisor
      if $CFG.get(:vpsadmin, :type) == :node
        loop do
          begin
            pool = osctl_parse(%i(pool show), name)
          rescue SystemCommandFailed
            next
          end

          break if pool[:state] == 'active'

          log(:info, "Waiting for osctld to import pool #{name}")
          sleep(10)
        end
      end

      log(:info, "Pool #{fs} is ready")
    end

    def pools(db)
      ret = []

      db.prepared(
        'SELECT filesystem FROM pools WHERE node_id = ?',
        $CFG.get(:vpsadmin, :node_id)
      ).each { |row| ret << row['filesystem'] }

      ret
    end
  end
end
