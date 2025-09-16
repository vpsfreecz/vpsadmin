require 'fileutils'
require 'json'
require 'socket'

module ConsoleServer
  class Control
    def self.run(*, **)
      control = new(*, **)
      control.serve
    end

    def initialize(state_dir)
      @state_dir = state_dir
      @consoles = Consoles.new(state_dir)
    end

    def serve
      sock_path = File.join(@state_dir, 'control.sock')

      begin
        File.unlink(sock_path)
      rescue Errno::ENOENT
        # pass
      end

      FileUtils.mkdir_p(File.dirname(sock_path))

      srv = UNIXServer.new(sock_path)

      loop do
        conn = srv.accept
        Thread.new { handle_client(conn) }
      end
    end

    protected

    def handle_client(conn)
      begin
        cmd = JSON.parse(conn.readline)
      rescue JSON::ParserError
        conn.close
      end

      case cmd['command']
      when 'start'
        begin
          @consoles.start(cmd['domain'], cmd['port'])
        rescue Consoles::ConsoleExists => e
          reply(conn, false, error: e.message)
        else
          reply(conn, true)
        end

      when 'stop'
        @consoles.stop(cmd['domain'])
        reply(conn, true)

      when 'attach'
        begin
          @consoles.attach(cmd['domain'], conn)
        rescue Consoles::ConsoleNotFound => e
          reply(conn, false, error: e.message)
        else
          reply(conn, true, close: false)
        end
      else
        reply(conn, false, error: "Unknown command #{cmd['command']}")
      end
    end

    def reply(client, status, error: nil, close: true)
      client.puts({ status:, error: }.compact.to_json)
      client.close if close
    end
  end
end
