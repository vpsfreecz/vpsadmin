module VpsAdmin::Supervisor
  class Vnc::Rpc
    def self.start(connection)
      rpc = new(connection.create_channel)
      rpc.start
    end

    def initialize(channel)
      @channel = channel
    end

    def start
      exchange = channel.direct('vnc:rpc')
      queue = channel.queue(
        'vnc:rpc',
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'rpc')

      queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
        request = Request.new(@channel, exchange, delivery_info, properties)
        request.process(payload)
      end
    end

    protected

    attr_reader :channel

    class Request
      def initialize(channel, exchange, delivery_info, properties)
        @channel = channel
        @exchange = exchange
        @delivery_info = delivery_info
        @properties = properties
      end

      def process(payload)
        begin
          req = JSON.parse(payload)
        rescue StandardError
          send_error('Unable to parse request as json')
          raise
        end

        handler = Handler.new
        cmd = req['command']

        unless handler.respond_to?(cmd)
          send_error("Command #{cmd.inspect} not found")
          return
        end

        begin
          response = handler.send(
            cmd,
            *req.fetch('args', []),
            **symbolize_hash_keys(req.fetch('kwargs', {}))
          )
        rescue StandardError => e
          send_error("#{e.class}: #{e.message}")
          raise
        else
          send_response(response)
        end

        nil
      end

      protected

      def send_response(response)
        reply({ status: true, response: })
      end

      def send_error(message)
        reply({ status: false, message: })
      end

      def reply(payload)
        @channel.ack(@delivery_info.delivery_tag)

        begin
          @exchange.publish(
            payload.to_json,
            persistent: true,
            content_type: 'application/json',
            routing_key: @properties.reply_to,
            correlation_id: @properties.correlation_id
          )
        rescue Bunny::ConnectionClosedError
          warn 'Vnc::Rpc#reply: connection closed, retry in 5s'
          sleep(5)
          retry
        end
      end

      def symbolize_hash_keys(hash)
        hash.transform_keys(&:to_sym)
      end
    end

    class Handler
      # @return [String] API URL
      def get_api_url
        ::SysConfig.select('value').where(
          category: 'core',
          name: 'api_url'
        ).take!.value
      end

      # @param [String] client_token
      # @return [Hash, nil]
      def get_vnc_target(client_token)
        vnc = ::VncToken
              .includes(vps: { node: :location })
              .joins(:client_token)
              .find_by(tokens: { token: client_token })

        return unless vnc && vnc.expiration > Time.now

        vnc.extend!

        {
          api_url: get_api_url,
          node_host: vnc.vps.node.ip_addr,
          node_port: 8082,
          node_token: vnc.node_token.token,
          vps_id: vnc.vps.id
        }
      end
    end
  end
end
