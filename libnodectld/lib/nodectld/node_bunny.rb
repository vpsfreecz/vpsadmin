require 'bunny'
require 'libosctl'
require 'singleton'

module NodeCtld
  class NodeBunny
    include Singleton

    class << self
      def connect
        instance
      end

      %i(create_channel exchange_name).each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      opts = {
        hosts: $CFG.get(:rabbitmq, :hosts),
        vhost: $CFG.get(:rabbitmq, :vhost),
        username: $CFG.get(:rabbitmq, :username),
        password: $CFG.get(:rabbitmq, :password),
      }

      logger = OsCtl::Lib::Logger.get

      if logger
        opts[:logger] = logger
      else
        opts[:log_file] = STDERR
      end

      @connection = ::Bunny.new(**opts)
      @connection.start
    end

    def create_channel
      @connection.create_channel
    end

    # @return [String]
    def exchange_name
      "node:#{$CFG.get(:vpsadmin, :node_name)}"
    end
  end
end
