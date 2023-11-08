require 'bunny'
require 'libosctl'
require 'singleton'

module NodeCtld
  class NodeBunny
    include Singleton
    include OsCtl::Lib::Utils::Log

    class << self
      def connect
        instance
      end

      %i(create_channel publish_wait publish_drop exchange_name queue_name).each do |v|
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
        # Our logger logs debug messages, which we do not need from bunny
        bunny_logger = logger.clone
        bunny_logger.level = Logger::INFO
        opts[:logger] = bunny_logger
      else
        opts[:log_file] = STDERR
      end

      @connection = ::Bunny.new(**opts)

      begin
        @connection.start
      rescue Bunny::TCPConnectionFailed
        log(:info, "Retry in 15s")
        sleep(15)
        retry
      end
    end

    def create_channel
      @connection.create_channel
    end

    # Call {Bunny::Exchange#publish} and handle connection closed errors
    def publish_wait(exchange, msg, **opts)
      exchange.publish(msg, **opts)
    rescue Bunny::ConnectionClosedError
      log(:warn, 'publish_wait: connection currently closed, retry in 15s')
      sleep(15)
      retry
    end

    # Call {Bunny::Exchange#publish} and drop message if the connection is closed
    def publish_drop(exchange, msg, **opts)
      exchange.publish(msg, **opts)
    rescue Bunny::ConnectionClosedError
      log(:warn, 'publish_drop: connection currently closed, message dropped')
    end

    # @return [String]
    def exchange_name
      "node:#{$CFG.get(:vpsadmin, :node_name)}"
    end

    # @param [String] name
    # @return [String]
    def queue_name(name)
      "node:#{$CFG.get(:vpsadmin, :node_name)}:#{name}"
    end

    def log_type
      'node-bunny'
    end
  end
end
