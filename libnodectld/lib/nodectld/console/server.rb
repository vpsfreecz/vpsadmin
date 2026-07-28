require 'base64'
require 'json'
require 'libosctl'
require 'securerandom'
require 'nodectld/console_events'

module NodeCtld
  class Console::Server
    include OsCtl::Lib::Utils::Log

    Session = Struct.new(
      :vps_id,
      :token,
      :client_id,
      :output_key,
      :key,
      :actor_user_id,
      :vps_console_id,
      :last_input
    )

    def initialize
      @configure_mutex = Mutex.new
      @output_mutex = Mutex.new
      @sessions = {}
      @consoles = {}
      @stopping = false
      @stopped = false
    end

    def start
      @queue = OsCtl::Lib::Queue.new
      @upkeep = Thread.new { run_upkeep }

      @channel = NodeBunny.create_channel
      @input_exchange = @channel.direct("console:#{$CFG.get(:vpsadmin, :node_name)}:input")
      @input_queue = @channel.queue(
        "console:#{$CFG.get(:vpsadmin, :node_name)}:input",
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      @input_queue.bind(@input_exchange)

      @output_exchange = @channel.direct("console:#{$CFG.get(:vpsadmin, :node_name)}:output")

      @input_queue.subscribe do |_delivery_info, _properties, payload|
        data = JSON.parse(payload)
        open_write_console(data)
      end

      control_exchange = @channel.direct("console:#{$CFG.get(:vpsadmin, :node_name)}:control")
      control_queue = @channel.queue(
        "console:#{$CFG.get(:vpsadmin, :node_name)}:control",
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      control_queue.bind(control_exchange)
      control_queue.subscribe do |_delivery_info, _properties, payload|
        close_console_client(JSON.parse(payload))
      end
    end

    def stop(reason: 'node_shutdown')
      sessions = nil
      consoles = nil

      @configure_mutex.synchronize do
        return if @stopping || @stopped

        @stopping = true
        sessions = @sessions.values
        consoles = @consoles.values
        @sessions = {}
        @consoles = {}
      end

      @queue << :stop if @queue
      @upkeep.join if @upkeep

      consoles.each { |console| close_console(console) }
      sessions.each do |session|
        publish_console_event('closed', session, reason:)
      end
    ensure
      @channel.close if @channel&.open?
      @configure_mutex.synchronize { @stopped = true } if sessions
    end

    def publish_output(data, **opts)
      @output_mutex.synchronize do
        NodeBunny.publish_wait(@output_exchange, data, **opts)
      end
    end

    def stats
      @configure_mutex.synchronize do
        @consoles.transform_values do |console|
          console.sessions.length
        end
      end
    end

    def log_type
      'console'
    end

    protected

    def open_write_console(data)
      token = data['session']
      client_id = normalize_client_id(data['client_id'])
      session_key = session_key(token, client_id)
      session = nil
      console = nil
      now = nil

      @configure_mutex.synchronize do
        return if @stopping

        session = @sessions[session_key]

        if session.nil?
          auth_context = authenticate(token)
          return if auth_context.nil?

          vps_id = auth_context.fetch('vps_id')

          now = Time.now
          session = Session.new(
            vps_id:,
            token:,
            client_id: client_id || SecureRandom.hex(16),
            output_key: client_id || token[0..19],
            key: session_key,
            actor_user_id: auth_context['user_id'],
            vps_console_id: auth_context['vps_console_id'],
            last_input: now
          )

          @sessions[session_key] = session
        end

        console = @consoles[session.vps_id]

        if console.nil?
          console = open_console(session.vps_id, session)
          @consoles[session.vps_id] = console
        elsif console.add_session(session)
          log(:info, "Adding client to console of VPS #{console.vps_id}")
        end

        publish_console_event('opened', session) if now
      end

      session.last_input = now || Time.now

      console.write(data['keys'], data['width'], data['height'])
    end

    def authenticate(token)
      RpcClient.run do |rpc|
        rpc.authenticate_console_session_context(token)
      end
    end

    def open_console(vps_id, session)
      log(:info, "Opening console of VPS #{vps_id}")
      c = Console::Wrapper.new(self, vps_id, session)
      c.start
      c
    end

    def run_upkeep
      loop do
        break if @queue.pop(timeout: 60) == :stop

        session_timeout = $CFG.get(:console, :session_timeout)
        prune_sessions(Time.now, session_timeout)
      end
    end

    def prune_sessions(now, session_timeout)
      closed = []

      @configure_mutex.synchronize do
        @consoles.delete_if do |_vps_id, console|
          # Remove dead consoles
          unless console.alive?
            console.sessions.each do |session|
              @sessions.delete(session.key)
              closed << [session, 'console_ended']
            end
            close_console(console)
            next(true)
          end

          # Prune inactive sessions
          console.sessions.delete_if do |session|
            if session.last_input + session_timeout < now
              @sessions.delete(session.key)
              closed << [session, 'session_timeout']
              true
            else
              false
            end
          end

          # Remove unused consoles
          if console.in_use?
            false
          else
            close_console(console)
            true
          end
        end
      end

      closed.each do |session, reason|
        publish_console_event('closed', session, reason:)
      end
    end

    def close_console_client(data)
      token = data['session']
      client_id = normalize_client_id(data['client_id'])
      return unless token && client_id

      session = nil

      @configure_mutex.synchronize do
        return if @stopping

        key = session_key(token, client_id)
        session = @sessions[key]
        return unless session && session.token == token

        console = @consoles[session.vps_id]
        return unless console

        console.sessions.delete(session)
        @sessions.delete(key)

        unless console.in_use?
          close_console(console)
          @consoles.delete(session.vps_id)
        end
      end

      publish_console_event(
        'closed',
        session,
        reason: normalize_close_reason(data['reason'])
      )
    end

    def close_console(console)
      log(:info, "Closing console of VPS #{console.vps_id}")
      console.stop
      console.sessions.each do |session|
        @sessions.delete(session.key)
      end
    end

    def session_key(token, client_id)
      client_id ? "client:#{client_id}:#{token}" : "legacy:#{token}"
    end

    def normalize_client_id(client_id)
      value = client_id.to_s
      value if /\A[0-9a-f]{32}\z/.match?(value)
    end

    def normalize_close_reason(reason)
      %w[client_closed router_timeout].include?(reason) ? reason : 'client_closed'
    end

    def publish_console_event(action, session, reason: nil)
      ConsoleEvents.publish(
        action:,
        vps_id: session.vps_id,
        client_id: session.client_id,
        actor_user_id: session.actor_user_id,
        vps_console_id: session.vps_console_id,
        reason:
      )
    end
  end
end
