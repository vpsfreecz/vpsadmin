require 'json'
require 'libosctl'
require 'securerandom'
require 'nodectld/node_bunny'

module NodeCtld
  class RpcClient
    SETUP_RETRIES = 10
    SETUP_RETRY_DELAY = 10

    class Error < ::StandardError; end

    class Timeout < Error; end
    class TransportError < Error; end
    class CleanupError < Error; end
    class Stopped < Error; end

    # Pending signal/nonlocal unwinds must survive a secondary cleanup failure.
    # rubocop:disable Lint/RescueException
    def self.run(stopped: nil)
      original = nil
      begin
        rpc = new(stopped:)
        yield(rpc)
      rescue Exception => e
        original = e
        raise
      ensure
        if rpc
          begin
            rpc.close
          rescue Exception => e
            raise unless original

            rpc.send(:log_secondary, e)
          end
        end
      end
    end
    # rubocop:enable Lint/RescueException

    include OsCtl::Lib::Utils::Log

    def initialize(stopped: nil)
      @response = nil
      @stopped = stopped
      @close_mutex = Mutex.new
      @closed = false
      @debug = $CFG.get(:rpc_client, :debug)
      setup_channel
    end

    def close
      @close_mutex.synchronize do
        return if @closed

        # Even failed close cannot issue another method on this channel.
        @closed = true
        begin
          channel_operation do
            @reply_queue.delete
            @channel.close
          end
          clear_channel
        rescue Error => e
          cause = e.is_a?(TransportError) ? e.cause : e
          raise CleanupError, 'RPC cleanup failed', cause:
        end
      end
    end

    def get_node_config
      send_read_request('get_node_config')
    end

    def list_pools
      send_read_request('list_pools')
    end

    # @param pool_id [Integer]
    # @param properties [Array<String>]
    def list_pool_dataset_properties(pool_id, properties)
      send_read_request('list_pool_dataset_properties', args: [pool_id, properties])
    end

    def list_vps_status_check
      send_read_request('list_vps_status_check')
    end

    def list_vps_network_interfaces
      send_read_request('list_vps_network_interfaces')
    end

    def find_vps_network_interface(vps_id, vps_name)
      send_read_request('find_vps_network_interface', args: [vps_id, vps_name])
    end

    def list_running_vps_ids
      send_read_request('list_running_vps_ids')
    end

    # @param pool_id [Integer]
    # @yieldparam [Hash] user namespace map
    def each_vps_user_namespace_map(pool_id, &block)
      from_id = nil

      loop do
        vps_maps = send_read_request(
          'list_vps_user_namespace_maps',
          args: [pool_id],
          kwargs: {
            from_id:,
            limit: 50
          }
        )

        break if vps_maps.empty?

        vps_maps.each(&block)
        from_id = vps_maps.last['vps_id']
      end
    end

    # @yieldparam [Hash] export
    def each_export(&block)
      from_id = nil

      loop do
        exports = send_read_request(
          'list_exports',
          kwargs: {
            from_id:,
            limit: 50
          }
        )

        break if exports.empty?

        exports.each(&block)
        from_id = exports.last['id']
      end

      nil
    end

    # @param token [String]
    # @return [Integer, nil] VPS id
    def authenticate_console_session(token)
      send_read_request('authenticate_console_session', args: [token])
    end

    def log_type
      'rpc'
    end

    protected

    attr_reader :lock, :condition, :call_id
    attr_accessor :response

    def setup_channel
      (SETUP_RETRIES + 1).times do |i|
        channel_operation { setup_channel_once }
        return nil
      rescue StandardError => e
        # Includes the final attempt and constructors failing after a partial
        # declaration. Never abandon a registered reply consumer on retry.
        raise unless e.is_a?(TransportError) && timeout_cause?(e) && i < SETUP_RETRIES

        log(:warn, "[#{i + 1}/#{SETUP_RETRIES}] Timeout while setting up RPC channel")
        wait_retry(SETUP_RETRY_DELAY)
      end
    end

    def setup_channel_once
      @channel = NodeBunny.create_channel(stopped: @stopped)
      @exchange = @channel.direct(NodeBunny.exchange_name)
      setup_reply_queue
    end

    def setup_reply_queue
      @lock = Mutex.new
      @condition = ConditionVariable.new
      that = self
      @reply_queue = @channel.queue('', exclusive: true)
      @reply_queue.bind(@exchange, routing_key: @reply_queue.name)

      @reply_queue.subscribe do |_delivery_info, properties, payload|
        if properties.correlation_id == that.call_id
          that.lock.synchronize do
            that.response = JSON.parse(payload)
            that.condition.signal
          end
        end
      end
    end

    def send_read_request(command, args: [], kwargs: {}, attempts: 30)
      send_request(command, args:, kwargs:, attempts:)
    end

    def send_write_request(command, args: [], kwargs: {}, attempts: 1)
      send_request(command, args:, kwargs:, attempts:)
    end

    def send_request(command, args: [], kwargs: {}, attempts: 1)
      check_stopped
      raise Error, 'RPC client is closed' if @closed

      attempt_counter = 1

      loop do
        begin
          resp = send_and_receive(command, args:, kwargs:)
        rescue Timeout
          log(:warn, "request id=#{@call_id[0..7]} attempt=#{attempt_counter}/#{attempts} timed out while waiting for a response")

          raise if attempt_counter >= attempts

          attempt_counter += 1
          wait_retry(5)
          next
        end

        return resp.fetch('response') if resp.fetch('status')

        if resp['retry']
          log(:debug, "response id=#{@call_id[0..7]} status=false message=#{resp['message']} retry=true")
          wait_retry(5)
          next
        end

        raise Error, @response.fetch('message', 'Server error')
      end
    end

    def send_and_receive(command, args:, kwargs:)
      @call_id = generate_uuid
      @response = nil

      if @debug
        t1 = Time.now
        log(:debug, "request id=#{@call_id[0..7]} command=#{command} args=#{args.inspect} kwargs=#{kwargs.inspect}")
      end

      message = { command:, args:, kwargs: }.to_json
      transport_call do
        NodeBunny.publish_wait(
          @exchange,
          message,
          persistent: true,
          content_type: 'application/json',
          routing_key: 'rpc',
          correlation_id: @call_id,
          reply_to: @reply_queue.name,
          stopped: @stopped,
          recovery_timeout: NodeBunny::RECOVERY_WAIT
        )
      end

      started = monotonic_time
      timeout = @stopped ? 1 : 5

      @lock.synchronize do
        loop do
          check_stopped
          break if @response

          @condition.wait(@lock, timeout)
          wait_secs = monotonic_time - started

          if @response
            break
          elsif wait_secs > $CFG.get(:rpc_client, :hard_timeout)
            raise Timeout, "No reply for #{wait_secs}s command=#{command}"
          elsif wait_secs > $CFG.get(:rpc_client, :soft_timeout)
            log(:warn, "request waiting secs=#{wait_secs} id=#{@call_id[0..7]} command=#{command}")
          end
        end
      end

      if @debug
        log(:debug, "response id=#{@call_id[0..7]} time=#{(Time.now - t1).round(3)}s value=#{@response.inspect}")
      end

      @response
    end

    # This boundary contains Bunny operations only. Catalog/JSON bugs are never
    # reclassified as a temporary network failure.
    def transport_call
      check_stopped
      yield
    rescue NodeBunny::Stopped => e
      raise Stopped, 'RPC operation stopped', cause: e
    rescue StandardError => e
      raise unless NodeBunny.transport_failure?(e)

      raise TransportError, 'RPC transport failed', cause: e
    end

    # Retire allocated channels even during an Interrupt; always re-raise it.
    # rubocop:disable Lint/RescueException
    def channel_operation
      entered = false
      transport_call do
        NodeBunny.channel_lifecycle(stopped: @stopped) do
          entered = true
          begin
            yield
          rescue Exception
            # Close the gate before releasing the application lifecycle lock.
            retire_channel
            raise
          end
        end
      end
    rescue Exception
      retire_channel unless entered
      raise
    end
    # rubocop:enable Lint/RescueException

    def timeout_cause?(error)
      NodeBunny.transport_cause(error.cause).is_a?(::Timeout::Error)
    end

    # These diagnostic paths run only with another exception already pending.
    # rubocop:disable Lint/RescueException
    def retire_channel
      return unless @channel

      NodeBunny.retire_channel(@channel, stopped: @stopped)
      clear_channel
    rescue Exception => e
      # Called only while another error is pending. NodeBunny retains ownership
      # of an incomplete retirement even after timeout/cooperative stop.
      log_secondary(e)
    end

    def clear_channel
      @channel = @exchange = @reply_queue = nil
    end

    def log_secondary(error)
      log(:warn, "Secondary RPC cleanup failure: #{error.class}")
    rescue Exception
      nil # diagnostics must not replace the pending original exception
    end
    # rubocop:enable Lint/RescueException

    def check_stopped
      raise Stopped, 'RPC operation stopped' if @stopped&.call
    end

    def wait_retry(seconds)
      deadline = monotonic_time + seconds
      loop do
        check_stopped
        remaining = deadline - monotonic_time
        return unless remaining > 0

        sleep(@stopped ? [remaining, 1].min : remaining)
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def generate_uuid
      SecureRandom.hex(20)
    end
  end
end
