require 'json'
require 'securerandom'

module VpsAdmin::ConsoleRouter
  class RpcClient
    class Error < ::StandardError; end

    class Timeout < Error; end

    SOFT_TIMEOUT = 10

    HARD_TIMEOUT = 60

    def initialize(channel)
      @channel = channel
      @exchange = @channel.direct('console:rpc')
      @response = nil
      @debug = false

      setup_reply_queue
    end

    def close
      @reply_queue.delete
    end

    def get_api_url
      send_request('get_api_url')
    end

    def get_session_node(vps_id, session)
      send_request('get_session_node', vps_id, session)
    end

    protected

    attr_reader :lock, :condition, :call_id
    attr_accessor :response

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

    def send_request(command, *args, **kwargs)
      @call_id = generate_uuid
      if @debug
        t1 = Time.now
        warn "request id=#{@call_id[0..7]} command=#{command} args=#{args.inspect} kwargs=#{kwargs.inspect}"
      end

      begin
        @exchange.publish(
          {
            command: command,
            args: args,
            kwargs: kwargs
          }.to_json,
          persistent: true,
          content_type: 'application/json',
          routing_key: 'rpc',
          correlation_id: @call_id,
          reply_to: @reply_queue.name
        )
      rescue Bunny::ConnectionClosedError
        warn 'rpc: connection closed, retry in 5s'
        sleep(5)
        retry
      end

      wait_secs = 0
      timeout = 5

      @lock.synchronize do
        loop do
          waited = @condition.wait(@lock, timeout)
          wait_secs += waited || timeout

          if @response
            break
          elsif wait_secs > HARD_TIMEOUT
            raise Timeout, "No reply for #{wait_secs}s command=#{command}"
          elsif wait_secs > SOFT_TIMEOUT
            warn "request waiting secs=#{wait_secs} id=#{@call_id[0..7]} command=#{command}"
          end
        end
      end

      warn "response id=#{@call_id[0..7]} time=#{(Time.now - t1).round(3)}s value=#{@response.inspect}" if @debug

      raise Error, @response.fetch('message', 'Server error') unless @response['status']

      @response['response']
    end

    def generate_uuid
      SecureRandom.hex(20)
    end
  end
end
