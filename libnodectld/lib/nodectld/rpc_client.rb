require 'json'
require 'libosctl'
require 'securerandom'

module NodeCtld
  class RpcClient
    class Error < ::StandardError; end

    class Timeout < Error; end

    def self.run
      rpc = new
      yield(rpc)
    ensure
      rpc.close if rpc
    end

    include OsCtl::Lib::Utils::Log

    def initialize
      retry_on_timeout('Timeout while creating channel') do
        @channel = NodeBunny.create_channel
      end

      retry_on_timeout('Timeout while creating exchange') do
        @exchange = @channel.direct(NodeBunny.exchange_name)
      end

      @response = nil
      @debug = $CFG.get(:rpc_client, :debug)

      retry_on_timeout('Timeout while setting up reply queue') do
        setup_reply_queue
      end
    end

    def close
      @reply_queue.delete
      @channel.close
    end

    def get_node_config
      send_request('get_node_config')
    end

    def list_pools
      send_request('list_pools')
    end

    # @param pool_id [Integer]
    # @param properties [Array<String>]
    def list_pool_dataset_properties(pool_id, properties)
      send_request('list_pool_dataset_properties', pool_id, properties)
    end

    def list_vps_status_check
      send_request('list_vps_status_check')
    end

    def list_vps_network_interfaces
      send_request('list_vps_network_interfaces')
    end

    def find_vps_network_interface(vps_id, vps_name)
      send_request('find_vps_network_interface', vps_id, vps_name)
    end

    def list_running_vps_ids
      send_request('list_running_vps_ids')
    end

    # @param pool_id [Integer]
    # @yieldparam [Hash] user namespace map
    def each_vps_user_namespace_map(pool_id, &block)
      from_id = nil

      loop do
        vps_maps = send_request(
          'list_vps_user_namespace_maps',
          pool_id,
          from_id:,
          limit: 50
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
        exports = send_request(
          'list_exports',
          from_id:,
          limit: 50
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
      send_request('authenticate_console_session', token)
    end

    def log_type
      'rpc'
    end

    protected

    attr_reader :lock, :condition, :call_id
    attr_accessor :response

    def retry_on_timeout(message, attempts: 10, delay: 10)
      attempts.times do |i|
        return yield
      rescue ::Timeout::Error
        log(:warn, "[#{i + 1}/#{attempts}] #{message}")
        sleep(delay)
      end

      yield
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

    def send_request(command, *, **)
      loop do
        resp = send_and_receive(command, *, **)
        return resp.fetch('response') if resp.fetch('status')

        if resp['retry']
          log(:debug, "response id=#{@call_id[0..7]} status=false message=#{resp['message']} retry=true")
          sleep(5)
          next
        end

        raise Error, @response.fetch('message', 'Server error')
      end
    end

    def send_and_receive(command, *args, **kwargs)
      @call_id = generate_uuid
      @response = nil

      if @debug
        t1 = Time.now
        log(:debug, "request id=#{@call_id[0..7]} command=#{command} args=#{args.inspect} kwargs=#{kwargs.inspect}")
      end

      NodeBunny.publish_wait(
        @exchange,
        {
          command:,
          args:,
          kwargs:
        }.to_json,
        persistent: true,
        content_type: 'application/json',
        routing_key: 'rpc',
        correlation_id: @call_id,
        reply_to: @reply_queue.name
      )

      wait_secs = 0
      timeout = 5

      @lock.synchronize do
        loop do
          waited = @condition.wait(@lock, timeout)
          wait_secs += waited || timeout

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

    def generate_uuid
      SecureRandom.hex(20)
    end
  end
end
