require 'bunny'
require 'yaml'

module VpsAdmin::ConsoleRouter
  class Router
    CacheEntry = Struct.new(
      :vps_id,
      :session,
      :node_name,
      :last_use,
      :last_check,
      :channel,
      :input_exchange,
      :output_queue,
      keyword_init: true
    )

    # How often verify session validity, in seconds
    SESSION_TIMEOUT = 15

    # Max number of messages fetched from rabbitmq queue for one request
    FETCH_COUNT = 256

    # @return [String]
    attr_reader :api_url

    def initialize
      cfg = parse_config

      @connection = Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
        log_file: $stderr
      )
      @connection.start

      @rpc = RpcClient.new(@connection.create_channel)
      @api_url = @rpc.get_api_url
      @cache = {}
      @mutex = Mutex.new
      @upkeep = Thread.new { run_upkeep }
    end

    # Check session validity
    # @param vps_id [Integer]
    # @param session [String]
    # @return [Boolean]
    def check_session(vps_id, session)
      get_session(vps_id, session).nil? ? false : true
    end

    # Write data to console and read from it
    # @param vps_id [Integer]
    # @param session [String]
    # @param keys [String, nil]
    # @param width [Integer]
    # @param height [Integer]
    # @return [String, nil]
    def read_write_console(vps_id, session, keys, width, height)
      sync do
        entry = get_session(vps_id, session)
        return if entry.nil?

        write_console(entry, keys, width, height)
        read_console(entry)
      end
    end

    protected
    # @param vps_id [Integer]
    # @param session [String]
    # @return [CacheEntry, nil]
    def get_session(vps_id, session)
      return if !session || !vps_id

      now = Time.now
      k = cache_key(vps_id, session)
      entry = nil

      sync do
        entry = @cache[k]

        if entry.nil? || (entry.last_check + SESSION_TIMEOUT < now)
          node_name = @rpc.get_session_node(vps_id, session)
          return if node_name.nil?

          entry.last_check = now if entry
        end

        if entry.nil?
          channel = @connection.create_channel

          input_exchange = channel.direct("console:#{node_name}:input")

          output_exchange = channel.direct("console:#{node_name}:output")
          output_queue = channel.queue(
            output_queue_name(vps_id, session),
            durable: true,
            arguments: { 'x-queue-type' => 'quorum' }
          )
          output_queue.bind(output_exchange, routing_key: routing_key(vps_id, session))

          entry = CacheEntry.new(
            vps_id:,
            session:,
            node_name:,
            last_use: now,
            last_check: now,
            channel:,
            input_exchange:,
            output_queue:
          )

          @cache[k] = entry
        else
          entry.last_use = now
        end
      end

      entry
    end

    # Read data from console
    # @param entry [CacheEntry]
    # @return [String]
    def read_console(entry)
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
    # @param entry [CacheEntry]
    # @param keys [String, nil]
    # @param width [Integer]
    # @param height [Integer]
    def write_console(entry, keys, width, height)
      data = {
        session: entry.session,
        width:,
        height:,
      }

      if keys && !keys.empty?
        data[:keys] = Base64.strict_encode64(keys)
      end

      begin
        entry.input_exchange.publish(
          data.to_json,
          content_type: 'application/json'
        )
      rescue Bunny::ConnectionClosedError
        return
      end
    end

    def run_upkeep
      loop do
        sleep(60)

        sync do
          now = Time.now

          @cache.delete_if do |key, entry|
            if entry.last_use + 60 < now
              entry.channel.close
              true
            else
              false
            end
          end
        end
      end
    end

    def parse_config
      path = File.join(__dir__, '../../../', 'config/rabbitmq.yml')
      YAML.safe_load(File.read(path))
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

    def sync(&block)
      if @mutex.owned?
        block.call
      else
        @mutex.synchronize(&block)
      end
    end
  end
end
