require 'base64'
require 'json'
require 'libosctl'

module NodeCtld
  class Console::Wrapper
    include OsCtl::Lib::Utils::Log

    # @return [Integer]
    attr_reader :vps_id

    # @return [Array<Console::Server::Session>]
    attr_reader :sessions

    # @param server [Console::Server]
    # @param vps_id [Integer]
    # @param session [Console::Server::Session]
    def initialize(server, vps_id, session)
      @server = server
      @vps_id = vps_id
      @sessions = [session]
      @width = nil
      @height = nil
      @alive = true
    end

    def start
      in_r, @in_w = IO.pipe
      @out_r, out_w = IO.pipe

      @pid = Process.spawn(
        'osctl', '-j', 'ct', 'console', @vps_id.to_s,
        in: in_r,
        out: out_w
      )

      in_r.close
      out_w.close

      @reader = Thread.new { read_from_pipe }

      publish("Welcome to vpsFree.cz Remote Console\r\n")
      send_write({ keys: Base64.strict_encode64("\n") })
    end

    def stop
      close
      @reader.join
      Process.wait(@pid)
    end

    # @param session [Console::Server::Session]
    # @return [Boolean] true if added
    def add_session(session)
      if @sessions.include?(session)
        false
      else
        @sessions << session
        true
      end
    end

    def in_use?
      @sessions.any?
    end

    def alive?
      @alive
    end

    def write(keys, width, height)
      data = {}

      data[:keys] = keys if keys

      if @width != width || @height != height
        @width = width
        @height = height
        data[:cols] = width
        data[:rows] = height
      end

      return if data.empty?

      send_write(data)
    end

    protected

    def send_write(data)
      @in_w.write("#{data.to_json}\n")
    end

    def read_from_pipe
      loop do
        begin
          data = @out_r.read_nonblock(4096)
        rescue IO::WaitReadable
          _, _, errs = IO.select([@out_r])

          if errs.any?
            @alive = false
            return
          end

          next
        end

        publish(data)
      end
    rescue IOError
      @alive = false
    end

    def publish(data)
      @sessions.each do |session|
        @server.publish_output(
          data,
          content_type: 'application/octet-stream',
          routing_key: routing_key(session)
        )
      rescue Bunny::ConnectionClosedError
        next
      end
    end

    def close
      @in_w.close
      @out_r.close
    end

    def routing_key(session)
      "#{@vps_id}-#{session.token[0..19]}"
    end
  end
end
