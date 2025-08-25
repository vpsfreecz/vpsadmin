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

      %i[create_channel publish_wait publish_drop exchange_name queue_name].each do |v|
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
        password: $CFG.get(:rabbitmq, :password)
      }

      logger = OsCtl::Lib::Logger.get

      if logger
        # Our logger logs debug messages, which we do not need from bunny
        bunny_logger = logger.clone
        bunny_logger.level = Logger::INFO
        opts[:logger] = bunny_logger
      else
        opts[:log_file] = $stderr
      end

      @connection = ::Bunny.new(**opts)

      begin
        @connection.start
      rescue Bunny::TCPConnectionFailed
        log(:info, 'Retry in 15s')
        sleep(15)
        retry
      end
    end

    # Call {Bunny::Session#create_channel} and handle connection errors
    #
    # If the connection is closed, this method blocks until bunny's auto-recovery
    # process fixes it and the channel can be created.
    #
    # @return [Bunny::Channel]
    def create_channel
      until @connection.open?
        log(:info, 'Waiting for recovery to create a channel')
        sleep(5)
      end

      begin
        @connection.create_channel
      rescue RuntimeError => e
        # Bunny returns RuntimeError when the connection is closed
        # and recovery is in progress
        raise unless e.message.include?('this connection is not open')

        sleep(5)

        until @connection.open?
          log(:info, 'Waiting for recovery to create a channel')
          sleep(5)
        end

        retry
      end
    end

    # Call {Bunny::Exchange#publish} and handle connection closed errors
    def publish_wait(exchange, msg, **)
      exchange.publish(msg, **)
    rescue Bunny::ConnectionClosedError
      log(:warn, 'publish_wait: connection currently closed, retry in 15s')
      sleep(15)
      retry
    end

    # Call {Bunny::Exchange#publish} and drop message if the connection is closed
    def publish_drop(exchange, msg, **)
      exchange.publish(msg, **)
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
