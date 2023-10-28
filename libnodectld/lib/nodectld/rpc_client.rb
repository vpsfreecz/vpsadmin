require 'json'
require 'securerandom'

module NodeCtld
  class RpcClient
    def self.run
      rpc = new
      yield(rpc)
    ensure
      rpc.close
    end

    def initialize
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct('node.rpc')
      @response = nil

      setup_reply_queue
    end

    def close
      @reply_queue.delete
      @channel.close
    end

    def list_pools
      send_request('list_pools', $CFG.get(:vpsadmin, :node_id))
    end

    # @param pool_id [Integer]
    # @param properties [Array<String>]
    def list_pool_dataset_properties(pool_id, properties)
      send_request('list_pool_dataset_properties', pool_id, properties)
    end

    def list_vps_status_check
      send_request('list_vps_status_check', $CFG.get(:vpsadmin, :node_id))
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
          that.response = JSON.parse(payload)['response']

          that.lock.synchronize { that.condition.signal }
        end
      end
    end

    def send_request(command, *args, **kwargs)
      @call_id = generate_uuid

      @exchange.publish(
        {
          command: command,
          args: args,
          kwargs: kwargs,
        }.to_json,
        content_type: 'application/json',
        routing_key: 'request',
        correlation_id: @call_id,
        reply_to: @reply_queue.name,
      )

      @lock.synchronize { @condition.wait(@lock) }

      @response
    end

    def generate_uuid
      SecureRandom.hex(20)
    end
  end
end
