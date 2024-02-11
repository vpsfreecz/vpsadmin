module VpsAdmin::Supervisor
  class Console::Rpc
    def self.start(connection)
      rpc = new(connection.create_channel)
      rpc.start
    end

    def initialize(channel)
      @channel = channel
    end

    def start
      exchange = channel.direct('console:rpc')
      queue = channel.queue(
        'console:rpc',
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
          warn 'Console::Rpc#reply: connection closed, retry in 5s'
          sleep(5)
          retry
        end
      end

      def symbolize_hash_keys(hash)
        Hash[hash.map { |k, v| [k.to_sym, v] }]
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

      # @param [Integer] vps_id
      # @param [String] session
      # @return [String, nil]
      def get_session_node(vps_id, session)
        now = Time.now
        console = ::VpsConsole
                  .includes(vps: { node: :location })
                  .find_by(vps_id:, token: session)

        return unless console && console.expiration > now

        console.update!(expiration: now + 60)
        console.vps.node.domain_name
      end
    end
  end
end
