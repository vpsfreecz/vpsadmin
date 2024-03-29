require 'fileutils'
require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Node
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    Pool = Struct.new(:name, :filesystem, :role, :online)

    def initialize
      @pools = {}
      @mutex = Mutex.new
    end

    def init
      fetch_pools.each do |pool|
        @mutex.synchronize do
          @pools[pool.name] = pool
        end
      end

      @pools.each_value do |pool|
        wait_for_pool(pool)
      end
    end

    def any_pools?
      @mutex.synchronize do
        @pools.any?
      end
    end

    def any_osctl_pools?
      @mutex.synchronize do
        !@pools.detect { |_, pool| pool.role == :hypervisor }.nil?
      end
    end

    def all_pools_up?
      @mutex.synchronize do
        @pools.each_value.all?(&:online)
      end
    end

    def set_all_pools_down
      @mutex.synchronize do
        @pools.each_value do |pool|
          pool.online = false
        end
      end
    end

    def pool_down(pool_name)
      @mutex.synchronize do
        next if @pools[pool_name].nil?

        @pools[pool_name].online = false
      end
    end

    def pool_up(pool_name)
      @mutex.synchronize do
        next if @pools[pool_name].nil?

        @pools[pool_name].online = true
      end
    end

    def log_type
      'node'
    end

    protected

    def wait_for_pool(pool)
      sv = "pool-#{pool.name}"

      # Wait for runit service pool-$name to finish
      until File.exist?(File.join('/run/service', sv, 'done'))
        log(:info, "Waiting for service #{sv} to finish")
        sleep(5)
      end

      # Wait for osctld to import the pool, if this node is a hypervisor
      if $CFG.get(:vpsadmin, :type) == :node
        loop do
          begin
            osctl_pool = osctl_parse(%i[pool show], pool.name)
          rescue SystemCommandFailed
            sleep(5)
            next
          end

          break if osctl_pool[:state] == 'active'

          log(:info, "Waiting for osctld to import pool #{pool.name}")
          sleep(10)
        end
      end

      log(:info, "Pool #{pool.filesystem} is ready")
      pool_up(pool.name)

      # Install pool hooks
      install_pool_hooks(pool)
    end

    def install_pool_hooks(pool)
      hook_dir = File.join('/', pool.name, 'hook/pool')

      unless Dir.exist?(hook_dir)
        log(:warn, "Pool hook dir not found at #{hook_dir.inspect}")
        return
      end

      %w[pre-import post-import pre-export].each do |hook|
        dst = File.join(hook_dir, hook)

        FileUtils.cp(
          File.join(NodeCtld.root, 'templates', 'pool', 'hook', hook),
          "#{dst}.new"
        )

        File.chmod(0o500, "#{dst}.new")
        File.rename("#{dst}.new", dst)
      end
    end

    def fetch_pools
      ret = []

      RpcClient.run do |rpc|
        rpc.list_pools.each do |pool|
          ret << Pool.new(
            pool['name'],
            pool['filesystem'],
            pool['role'].to_sym,
            false
          )
        end
      end

      ret
    end
  end
end
