require 'libosctl'
require 'nodectld/db'
require 'nodectld/utils'
require 'singleton'
require 'thread'

module NodeCtld
  # {Shaper} configures shaper on the host's interfaces
  class Shaper
    include Singleton
    include OsCtl::Lib::Utils::Log
    include Utils::System

    class << self
      # Initialize the shaper on host interfaces
      def init_node
        instance.init_node
      end

      # Reconfigure maximum tx/rx bandwidth for all interfaces
      # @param tx [Integer] bytes per second
      # @param rx [Integer] bytes per second
      def update_root(tx, rx)
        instance.update_root(tx, rx)
      end

      # Reset shaper on all interfaces
      def flush
        instance.flush
      end

      # Initialize shaper on all interfaces
      def init(db)
        instance.init(db)
      end

      # Reinitialize shaper on all interfaces
      # @param db [Db]
      def reinit(db)
        instance.reinit(db)
      end
    end

    def initialize
      @mutex = Mutex.new
    end

    def init_node
      sync { safe_init_node }
    end

    def update_root(tx, rx)
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)

      sync do
        host_netifs.each do |netif|
          tc("qdisc delete root dev #{netif}", [2])

          if tx > 0
            tc("qdisc add root dev #{netif} cake bandwidth #{tx}bit")
          end
        end
      end
    end

    def flush
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)

      sync do
        host_netifs.each do |netif|
          tc("qdisc delete root dev #{netif}", [2])
        end
      end
    end

    def init(db)
      sync do
        safe_init_node
      end
    end

    def reinit(db)
      sync do
        flush
        safe_init_node
      end
    end

    def log_type
      'shaper'
    end

    protected
    def safe_init_node
      host_netifs = $CFG.get(:vpsadmin, :net_interfaces)
      max_tx = $CFG.get(:vpsadmin, :max_tx)

      # Setup main host interfaces
      host_netifs.each do |netif|
        tc("qdisc delete root dev #{netif}", [2])

        if max_tx > 0
          tc("qdisc add root dev #{netif} cake bandwidth #{max_tx}bit")
        end
      end
    end

    def tc(arg, valid_rcs = [])
      syscmd("#{$CFG.get(:bin, :tc)} #{arg}", valid_rcs: valid_rcs)
    end

    def sync
      if @mutex.owned?
        yield
      else
        @mutex.synchronize { yield }
      end
    end
  end
end
