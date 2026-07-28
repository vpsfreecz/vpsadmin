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
      :control_exchange,
      :client_id
    )

    # How often verify session validity, in seconds
    SESSION_TIMEOUT = 15

    # Max number of messages fetched from rabbitmq queue for one request
    FETCH_COUNT = 256

    # @return [String]
    attr_reader :api_url

    def initialize(
      connection: nil,
      config: nil,
      config_path: nil,
      rpc_client: RpcClient,
      start_upkeep: true
    )
      @rpc_client = rpc_client
      @connection = connection || build_connection(config || parse_config(config_path))
      @connection.start unless connection

      @rpc_client.run(@connection) do |rpc|
        @api_url = rpc.get_api_url
      end

      @cache = {}
      @mutex = Mutex.new
      @upkeep = Thread.new { run_upkeep } if start_upkeep
    end

    # Check session validity
    # @param vps_id [Integer]
    # @param session [String]
    # @return [Boolean]
    def check_session(vps_id, session, client_id = nil)
      !get_session(vps_id, session, client_id).nil?
    end

    # Write data to console and read from it
    # @param vps_id [Integer]
    # @param session [String]
    # @param keys [String, nil]
    # @param width [Integer]
    # @param height [Integer]
    # @return [String, nil]
    def read_write_console(vps_id, session, keys, width, height, client_id: nil)
      sync do
        entry = get_session(vps_id, session, client_id)
        return if entry.nil?

        write_console(entry, keys, width, height)
        read_console(entry)
      end
    end

    # Close a browser console client.
    #
    # The control exchange is additive. When routed to an older NodeCtld with
    # no matching queue, the message is simply dropped and the legacy inactivity
    # timeout closes the console session.
    #
    # @param vps_id [Integer]
    # @param session [String]
    # @param client_id [String]
    # @return [Boolean]
    def close_console(vps_id, session, client_id)
      client_id = normalize_client_id(client_id)
      return false unless session && vps_id && client_id

      sync do
        entry = @cache.delete(cache_key(vps_id, session, client_id))
        return false if entry.nil?

        publish_close(entry, 'client_closed')
        delete_client_queue(entry)
        entry.channel.close
        true
      end
    end

    protected

    # @param vps_id [Integer]
    # @param session [String]
    # @return [CacheEntry, nil]
    def get_session(vps_id, session, client_id = nil)
      return if !session || !vps_id

      client_id = normalize_client_id(client_id)
      now = Time.now
      k = cache_key(vps_id, session, client_id)
      entry = nil

      sync do
        entry = @cache[k]

        if entry.nil? || (entry.last_check + SESSION_TIMEOUT < now)
          node_name = @rpc_client.run(@connection) do |rpc|
            rpc.get_session_node(vps_id, session)
          end

          return if node_name.nil?

          entry.last_check = now if entry
        end

        if entry.nil?
          channel = @connection.create_channel

          input_exchange = channel.direct("console:#{node_name}:input")

          output_exchange = channel.direct("console:#{node_name}:output")
          output_queue = channel.queue(
            output_queue_name(vps_id, session, client_id),
            durable: true,
            arguments: { 'x-queue-type' => 'quorum' }
          )
          output_queue.bind(
            output_exchange,
            routing_key: routing_key(vps_id, session, client_id)
          )
          if client_id
            output_queue.bind(
              output_exchange,
              routing_key: routing_key(vps_id, session)
            )
          end

          control_exchange =
            if client_id
              channel.direct("console:#{node_name}:control")
            end

          entry = CacheEntry.new(
            vps_id:,
            session:,
            node_name:,
            last_use: now,
            last_check: now,
            channel:,
            input_exchange:,
            output_queue:,
            control_exchange:,
            client_id:
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
        # ignore
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
        height:
      }
      data[:client_id] = entry.client_id if entry.client_id

      if keys && !keys.empty?
        data[:keys] = Base64.strict_encode64(keys)
      end

      begin
        entry.input_exchange.publish(
          data.to_json,
          content_type: 'application/json'
        )
      rescue Bunny::ConnectionClosedError
        # return
      end
    end

    def run_upkeep
      loop do
        sleep(60)

        sync do
          prune_cache(Time.now)
        end
      end
    end

    def prune_cache(now)
      @cache.delete_if do |_key, entry|
        if entry.last_use + 60 < now
          publish_close(entry, 'router_timeout') if entry.client_id
          delete_client_queue(entry)
          entry.channel.close
          true
        else
          false
        end
      end
    end

    def build_connection(cfg)
      Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
        log_file: $stderr
      )
    end

    def parse_config(path = nil)
      path ||= File.join(__dir__, '../../../', 'config/rabbitmq.yml')
      YAML.safe_load_file(path)
    end

    def cache_key(vps_id, session, client_id = nil)
      legacy_key = "#{vps_id}-#{session}"
      client_id ? "#{legacy_key}-#{client_id}" : legacy_key
    end

    def output_queue_name(vps_id, session, client_id = nil)
      "console:output:#{routing_key(vps_id, session, client_id)}"
    end

    def routing_key(vps_id, session, client_id = nil)
      "#{vps_id}-#{client_id || session[0..19]}"
    end

    def normalize_client_id(client_id)
      value = client_id.to_s
      value if /\A[0-9a-f]{32}\z/.match?(value)
    end

    def publish_close(entry, reason)
      entry.control_exchange.publish(
        {
          session: entry.session,
          client_id: entry.client_id,
          reason:
        }.to_json,
        content_type: 'application/json'
      )
    rescue Bunny::ConnectionClosedError
      nil
    end

    def delete_client_queue(entry)
      entry.output_queue.delete if entry.client_id
    rescue Bunny::ConnectionClosedError
      nil
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
