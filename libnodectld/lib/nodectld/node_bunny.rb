require 'bunny'
require 'libosctl'
require 'monitor'
require 'singleton'
require 'socket'

module NodeCtld
  class NodeBunny
    include Singleton
    include OsCtl::Lib::Utils::Log

    RECOVERY_WAIT = 30
    WAIT_SLICE = 1
    Retirement = Struct.new(:channel, :transport, :reader, :generation, :complete)
    class RecoveryTimeout < ::Timeout::Error; end
    class RecoveryFailed < IOError; end
    class Stopped < StandardError; end

    TRANSPORT_ERRORS = [
      ::Timeout::Error, Bunny::ConnectionClosedError, Bunny::ConnectionAlreadyClosed,
      Bunny::ChannelAlreadyClosed, Bunny::TCPConnectionFailed,
      Bunny::ConnectionForced, Bunny::ForcedConnectionCloseError,
      IOError, SocketError, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED,
      Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH
    ].freeze

    class << self
      def connect
        instance
      end

      %i[create_channel channel_lifecycle retire_channel publish_wait publish_drop exchange_name queue_name].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end

      # Only classify errors at a Bunny call boundary. Its network wrappers can
      # contain arbitrary exceptions, including permanent broker/parser errors.
      def transport_cause(error)
        seen = []
        loop do
          return error if seen.include?(error)

          seen << error
          underlying = case error
                       when Bunny::NetworkFailure, Bunny::ConnectionClosedError, Bunny::ConnectionAlreadyClosed
                         error.cause
                       when Bunny::NetworkErrorWrapper then error.other
                       when Bunny::ChannelAlreadyClosed
                         error.channel.instance_variable_get(:@last_channel_error)
                       end
          return error unless underlying

          error = underlying
        end
      end

      def transport_failure?(error)
        TRANSPORT_ERRORS.any? { |klass| transport_cause(error).is_a?(klass) }
      end
    end

    def initialize
      initialize_synchronization

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
      @connection.before_recovery_attempt_starts { connection_recovery_started }
      @connection.after_recovery_completed { connection_recovered }

      begin
        @connection.start
      rescue Bunny::TCPConnectionFailed
        log(:info, 'Retry in 15s')
        sleep(15)
        retry
      end
    end

    # A reentrant lifecycle lock lets RPC setup hold the same open/close barrier
    # across exchange, queue and consumer declarations. Recovery never takes it.
    def channel_lifecycle(stopped: nil)
      @channel_creation_mutex.synchronize do
        wait_for_recovery(stopped:)
        yield
      end
    end

    # Cleanup must preserve signal and programming failures as well as timeouts.
    # rubocop:disable Lint/RescueException
    def create_channel(stopped: nil)
      channel_lifecycle(stopped:) do
        channels_before = registered_channels

        begin
          @connection.create_channel
        rescue Exception => e # preserve the original constructor failure
          if e.is_a?(RuntimeError) && e.message.start_with?('this connection is not open')
            wait_for_recovery(stopped:)
            retry
          end

          allocated = registered_channels - channels_before
          if allocated.any? || self.class.transport_failure?(e)
            begin
              recover_connection(allocated, stopped:)
            rescue Exception => recovery_error
              begin
                log(:warn, "Channel retirement pending after #{recovery_error.class}")
              rescue Exception
                nil # preserve the pending constructor failure
              end
            end
          end
          raise
        end
      end
    end
    # rubocop:enable Lint/RescueException

    # The token belongs to this exact channel, not its reusable numeric ID.
    # Stop/timeout leaves it pending behind the publisher/creation gate.
    def retire_channel(channel, stopped: nil)
      @channel_creation_mutex.synchronize do
        entry = register_retirement(channel)
        return entry if entry.complete

        close_old_transport(entry.transport)
        wait_for_retirement(entry, stopped:)
        entry
      end
    end

    def publish_wait(exchange, msg, stopped: nil, recovery_timeout: nil, **)
      acquired = false
      acquire_publisher(stopped:, recovery_timeout:)
      acquired = true
      exchange.publish(msg, **)
    rescue Bunny::ConnectionClosedError => e
      raise unless self.class.transport_failure?(e)
      raise Stopped, 'RPC recovery stopped' if stopped&.call

      log(:warn, 'publish_wait: connection currently closed, retry in 15s')
      release_publisher if acquired
      acquired = false
      wait_retry(15, stopped:)
      retry
    ensure
      release_publisher if acquired
    end

    def publish_drop(exchange, msg, **)
      acquired = @connection_recovery_mutex.synchronize do
        next false if @connection_recovering || (@publisher_owner && @publisher_owner != Thread.current)

        @publisher_owner = Thread.current
        @publisher_depth += 1
        true
      end
      return false unless acquired

      exchange.publish(msg, **)
      true
    rescue Bunny::ConnectionClosedError => e
      raise unless self.class.transport_failure?(e)

      log(:warn, 'publish_drop: connection currently closed, message dropped')
      false
    ensure
      release_publisher if acquired
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

    def initialize_synchronization
      @channel_creation_mutex = Monitor.new
      @connection_recovery_mutex = Monitor.new
      @connection_recovery_condition = @connection_recovery_mutex.new_cond
      @connection_recovery_generation = 0
      @connection_recovering = false
      @retirements = {}.compare_by_identity
      @publisher_owner = nil
      @publisher_depth = 0
    end

    def acquire_publisher(stopped: nil, recovery_timeout: nil)
      deadline = monotonic_time + recovery_timeout if recovery_timeout
      @connection_recovery_mutex.synchronize do
        recovery_wait(deadline, stopped:) while @connection_recovering || (@publisher_owner && @publisher_owner != Thread.current)
        raise Stopped, 'RPC recovery stopped' if stopped&.call

        @publisher_owner = Thread.current
        @publisher_depth += 1
      end
    end

    def release_publisher
      @connection_recovery_mutex.synchronize do
        @publisher_depth -= 1
        @publisher_owner = nil if @publisher_depth == 0
        @connection_recovery_condition.broadcast
      end
    end

    def register_retirement(channel)
      @connection_recovery_mutex.synchronize do
        entry = channel.instance_variable_get(:@nodectld_retirement)
        return entry if entry

        entry = Retirement.new(
          channel:, transport: @connection.transport,
          reader: @connection.instance_variable_get(:@reader_loop),
          generation: @connection_recovery_generation, complete: false
        )
        channel.instance_variable_set(:@nodectld_retirement, entry)
        @retirements[channel] = entry
        @connection_recovering = true
        entry
      end
    end

    # Bunny uses one connection-wide continuation queue for channel.open-ok.
    # A timed-out open therefore poisons the connection for the next channel
    # creation. Close the transport to make Bunny reset that queue and recover
    # all existing channels before the timeout is propagated to the caller.
    def recover_connection(timed_out_channels, stopped: nil)
      entries = timed_out_channels.map { |channel| register_retirement(channel) }
      @connection_recovery_mutex.synchronize { @connection_recovering = true }
      log(:warn, 'Channel creation timed out, recovering RabbitMQ connection')
      close_old_transport(@connection.transport)
      entries.each { |entry| wait_for_retirement(entry, stopped:) }
      wait_for_recovery(stopped:)
    end

    # Close the publisher gate and remove channels whose open timed out after
    # the old transport is closed and before Bunny recovers registered channels
    # on the new transport.
    def connection_recovery_started
      @connection_recovery_mutex.synchronize do
        @connection_recovering = true
      end
      transport = @connection.transport
      reader = @connection.instance_variable_get(:@reader_loop)
      close_old_transport(transport)
      stop_old_reader(reader)
      deadline = monotonic_time + RECOVERY_WAIT
      @connection_recovery_mutex.synchronize do
        recovery_wait(deadline) while @publisher_owner && @publisher_owner != Thread.current
      end

      # Drain again: a request can arrive while the first batch is being reaped.
      loop do
        entries = @connection_recovery_mutex.synchronize { @retirements.values.dup }
        break if entries.empty?

        entries.each { |entry| complete_retirement(entry, deadline) }
      end
    end

    def connection_recovered
      pending = @connection_recovery_mutex.synchronize do
        pending = @retirements.any?
        @connection_recovering = pending
        @connection_recovery_generation += 1
        @connection_recovery_condition.broadcast
        pending
      end
      # A late request may have missed the final pre-recovery batch. The next
      # existing Bunny recovery cycle must retire it; this generation is not proof.
      close_old_transport(@connection.transport) if pending
    end

    def complete_retirement(entry, deadline)
      close_old_transport(entry.transport)
      stop_old_reader(entry.reader, deadline:)
      reap_consumer_pool(entry.channel, deadline)
      @connection.unregister_channel(entry.channel) if registered_channels.any? { |ch| ch.equal?(entry.channel) }
      raise RecoveryFailed, 'RPC channel remains registered' if registered_channels.any? { |ch| ch.equal?(entry.channel) }

      @connection_recovery_mutex.synchronize do
        entry.complete = true
        @retirements.delete(entry.channel)
        @connection_recovery_condition.broadcast
      end
    end

    def close_old_transport(transport)
      return if transport.closed?

      if @connection.transport.equal?(transport)
        @connection.close_transport
      else
        transport.close
      end
      raise RecoveryFailed, 'RPC transport closure was not proved' unless transport.closed?
    end

    # Pinned Bunny resumes recovery on either its old reader or the publisher.
    # In the latter case, close/stop/join proves no old frame can still dispatch.
    def stop_old_reader(reader, deadline: monotonic_time + RECOVERY_WAIT)
      return unless reader

      reader.stop
      thread = reader.instance_variable_get(:@thread)
      if thread == Thread.current
        # ReaderLoop enters Session recovery only after run_once failed and
        # @network_is_down prevents another old-frame dispatch on return.
        raise RecoveryFailed, 'RPC reader is outside recovery' unless reader.instance_variable_get(:@network_is_down)

        return
      end

      join_worker(thread, deadline) if thread
    end

    def reap_consumer_pool(channel, deadline)
      pool = channel.instance_variable_get(:@work_pool)
      return unless pool

      threads = Array(pool.threads)
      raise RecoveryFailed, 'RPC consumer cannot retire itself' if threads.include?(Thread.current)

      pool.shutdown
      pool.kill
      threads.each do |thread|
        join_worker(thread, deadline)
      end
    end

    def join_worker(thread, deadline)
      return unless thread.alive?

      remaining = deadline - monotonic_time
      raise RecoveryTimeout, 'RPC worker retirement timed out' unless remaining > 0 && thread.join(remaining)
    end

    def wait_for_retirement(entry, stopped: nil)
      deadline = monotonic_time + RECOVERY_WAIT
      @connection_recovery_mutex.synchronize do
        recovery_wait(deadline, stopped:) until entry.complete
      end
    end

    def wait_for_recovery(stopped: nil)
      deadline = monotonic_time + RECOVERY_WAIT
      @connection_recovery_mutex.synchronize do
        recovery_wait(deadline, stopped:) while @connection_recovering || !@connection.open?
        raise Stopped, 'RPC recovery stopped' if stopped&.call
      end
    end

    def recovery_wait(deadline, stopped: nil)
      raise Stopped, 'RPC recovery stopped' if stopped&.call

      if deadline.nil?
        @connection_recovery_condition.wait(WAIT_SLICE)
        return
      end

      remaining = deadline - monotonic_time
      raise RecoveryTimeout, 'RPC recovery is still pending' unless remaining > 0

      @connection_recovery_condition.wait([remaining, WAIT_SLICE].min)
    end

    def wait_retry(seconds, stopped: nil)
      deadline = monotonic_time + seconds
      loop do
        raise Stopped, 'RPC recovery stopped' if stopped&.call

        remaining = deadline - monotonic_time
        break unless remaining > 0

        sleep(stopped ? [remaining, WAIT_SLICE].min : remaining)
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
