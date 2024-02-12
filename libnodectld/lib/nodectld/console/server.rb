require 'base64'
require 'json'
require 'libosctl'

module NodeCtld
  class Console::Server
    include OsCtl::Lib::Utils::Log

    Session = Struct.new(
      :vps_id,
      :token,
      :last_input,
      keyword_init: true
    )

    def initialize
      @configure_mutex = Mutex.new
      @output_mutex = Mutex.new
      @sessions = {}
      @consoles = {}
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
    end

    def publish_output(data, **opts)
      @output_mutex.synchronize do
        @output_exchange.publish(data, **opts)
      end
    end

    def stats
      @configure_mutex.synchronize do
        @consoles.to_h do |vps_id, console|
          [vps_id, console.sessions.length]
        end
      end
    end

    def log_type
      'console'
    end

    protected

    def open_write_console(data)
      token = data['session']
      session = nil
      console = nil
      now = nil

      @configure_mutex.synchronize do
        session = @sessions[token]

        if session.nil?
          vps_id = authenticate(token)
          return if vps_id.nil?

          now = Time.now
          session = Session.new(
            vps_id:,
            token:,
            last_input: now
          )

          @sessions[token] = session
        end

        console = @consoles[session.vps_id]

        if console.nil?
          console = open_console(session.vps_id, session)
          @consoles[session.vps_id] = console
        elsif console.add_session(session)
          log(:info, "Adding client to console of VPS #{console.vps_id}")
        end
      end

      session.last_input = now || Time.now

      console.write(data['keys'], data['width'], data['height'])
    end

    def authenticate(token)
      RpcClient.run do |rpc|
        rpc.authenticate_console_session(token)
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
        @queue.pop(timeout: 60)

        session_timeout = $CFG.get(:console, :session_timeout)
        now = Time.now

        @configure_mutex.synchronize do
          @consoles.delete_if do |vps_id, console|
            # Remove dead consoles
            unless console.alive?
              close_console(console)
              next(true)
            end

            # Prune inactive sessions
            console.sessions.delete_if do |session|
              if session.last_input + session_timeout < now
                @sessions.delete(session.token)
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
      end
    end

    def close_console(console)
      log(:info, "Closing console of VPS #{console.vps_id}")
      console.stop
      console.sessions.each { |session| @sessions.delete(session.token) }
    end
  end
end
