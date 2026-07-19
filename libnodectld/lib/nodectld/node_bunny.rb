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
      @channel_creation_mutex = Mutex.new
      @connection_recovery_mutex = Mutex.new
      @connection_recovery_condition = ConditionVariable.new
      @connection_recovery_generation = 0
      @timed_out_channels = []

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
      @connection.before_recovery_attempt_starts { remove_timed_out_channels }
      @connection.after_recovery_completed { connection_recovered }

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
      @channel_creation_mutex.synchronize do
        until @connection.open?
          log(:info, 'Waiting for recovery to create a channel')
          sleep(5)
        end

        channels_before = registered_channels

        begin
          @connection.create_channel
        rescue ::Timeout::Error
          recover_connection(registered_channels - channels_before)
          raise
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
      true
    rescue Bunny::ConnectionClosedError
      log(:warn, 'publish_drop: connection currently closed, message dropped')
      false
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

    protected

    # Bunny uses one connection-wide continuation queue for channel.open-ok.
    # A timed-out open therefore poisons the connection for the next channel
    # creation. Close the transport to make Bunny reset that queue and recover
    # all existing channels before the timeout is propagated to the caller.
    def recover_connection(timed_out_channels)
      generation = @connection_recovery_mutex.synchronize do
        @timed_out_channels.concat(timed_out_channels)
        @connection_recovery_generation
      end

      log(:warn, 'Channel creation timed out, recovering RabbitMQ connection')
      @connection.close_transport

      @connection_recovery_mutex.synchronize do
        @connection_recovery_condition.wait(@connection_recovery_mutex) while @connection_recovery_generation == generation
      end
    end

    # Remove channels whose open timed out after the old transport is closed
    # and before Bunny recovers registered channels on the new transport.
    def remove_timed_out_channels
      channels = @connection_recovery_mutex.synchronize do
        ret = @timed_out_channels
        @timed_out_channels = []
        ret
      end

      channels.each { |channel| @connection.unregister_channel(channel) }
    end

    def connection_recovered
      @connection_recovery_mutex.synchronize do
        @connection_recovery_generation += 1
        @connection_recovery_condition.broadcast
      end
    end

    # Bunny has no public channel registry. Keep the compatibility-sensitive
    # access isolated so a timed-out opening channel can be excluded from
    # automatic recovery instead of leaking on every retry.
    def registered_channels
      mutex = @connection.instance_variable_get(:@channel_mutex)
      channels = @connection.instance_variable_get(:@channels)

      mutex.synchronize { channels.values.dup }
    end
  end
end
