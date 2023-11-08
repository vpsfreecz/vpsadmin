require 'bunny'
require 'yaml'

module VpsAdmin::ConsoleRouter
  class Router
    CacheEntry = Struct.new(
      :node_name,
      :last_check,
      :input_exchange,
      :output_queue,
      keyword_init: true,
    )

    # How often verify session validity, in seconds
    SESSION_TIMEOUT = 15

    # Max number of messages fetched from rabbitmq queue for one request
    FETCH_COUNT = 256

    # @return [String]
    attr_reader :api_url

    def initialize
      cfg = parse_config

      connection = Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
        log_file: STDERR,
      )
      connection.start

      @channel = connection.create_channel
      @rpc = RpcClient.new(@channel)
      @api_url = @rpc.get_api_url
      @cache = {}
    end

    # Read data from console
    # @param vps_id [Integer]
    # @param session [String]
    # @return [String]
    def read_console(vps_id, session)
      entry = get_cache(vps_id, session)
      ret = ''

      begin
        FETCH_COUNT.times do
          delivery_info, properties, payload = entry.output_queue.pop
          break if payload.nil?

          ret << payload
        end
      rescue Timeout::Error
      end

      ret
    end

    # Write data to console
    # @param vps_id [Integer]
    # @param session [String]
    # @param keys [String, nil]
    # @param width [Integer]
    # @param height [Integer]
    def write_console(vps_id, session, keys, width, height)
      entry = get_cache(vps_id, session)

      data = {
        session: session,
        width: width,
        height: height,
      }

      if keys && !keys.empty?
        data[:keys] = Base64.strict_encode64(keys)
      end

      begin
        entry.input_exchange.publish(
          data.to_json,
          content_type: 'application/json',
        )
      rescue Bunny::ConnectionClosedError
        return
      end
    end

    # Check session validity
    # @param vps_id [Integer]
    # @param session [String]
    # @return [Boolean]
    def check_session(vps_id, session)
      return false if !session || !vps_id

      now = Time.now
      k = cache_key(vps_id, session)
      entry = @cache[k]

      if entry.nil? || (entry.last_check + SESSION_TIMEOUT < now)
        node_name = @rpc.get_session_node(vps_id, session)
        return false if node_name.nil?

        entry.last_check = now if entry
      end

      if entry.nil?
        input_exchange = @channel.direct("console:#{node_name}:input")

        output_exchange = @channel.direct("console:#{node_name}:output")
        output_queue = @channel.queue(output_queue_name(vps_id, session))
        output_queue.bind(output_exchange, routing_key: routing_key(vps_id, session))

        entry = CacheEntry.new(
          node_name:,
          last_check: now,
          input_exchange:,
          output_queue:,
        )

        @cache[k] = entry
      end

      true
    end

    protected
    def parse_config
      path = File.join(__dir__, '../../../', 'config/rabbitmq.yml')
      YAML.safe_load(File.read(path))
    end

    def get_cache(vps_id, session)
      @cache[ cache_key(vps_id, session) ]
    end

    def cache_key(vps_id, session)
      "#{vps_id}-#{session}"
    end

    def output_queue_name(vps_id, session)
      "console:output:#{vps_id}-#{session[0..19]}"
    end

    def routing_key(vps_id, session)
      "#{vps_id}-#{session[0..19]}"
    end
  end
end
