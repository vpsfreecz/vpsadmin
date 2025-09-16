require 'base64'
require 'fileutils'
require 'socket'

module ConsoleServer
  class Server
    attr_reader :domain, :port

    def initialize(domain, port)
      @domain = domain
      @port = port
      @clients = {}
      @cols = 80
      @rows = 25
      @mutex = Mutex.new
      @resize_queue = Queue.new
    end

    def start
      @qemu_thread = Thread.new { run_console }
      @resize_thread = Thread.new { run_resize }
    end

    def stop
      @stop = true

      @srv.close
      @qemu && @qemu.close
      @qemu_thread.join

      @resize_queue << :stop
      @resize_thread.join

      @mutex.synchronize do
        @clients.each_key(&:close)
      end
    end

    def attach(client)
      @mutex.synchronize do
        @clients[client] = ''
      end
    end

    protected

    def run_console
      @srv = TCPServer.new('localhost', @port)

      loop do
        begin
          @qemu = @srv.accept
        rescue IOError
          break
        end

        warn "Qemu for #{@domain} connected"
        handle_io(@qemu)
      end
    end

    def handle_io(qemu)
      loop do
        read_sockets = @mutex.synchronize { [qemu] + @clients.keys }

        begin
          to_read, = IO.select(read_sockets, nil, nil, 1)
        rescue IOError
          break
        end

        next if to_read.nil?

        to_read.each do |io|
          if io == qemu
            begin
              data = qemu.readpartial(16 * 1024)
            rescue IOError
              warn "Qemu for #{@domain} disconnected during read"
              return
            end

            @mutex.synchronize { @clients.keys }.each do |client|
              client.write(data)
            rescue IOError
              warn "Client for domain #{@domain} disconnected during write"
              @mutex.synchronize { @clients.delete(io) }
            end

            next
          end

          next unless @mutex.synchronize { @clients.include?(io) }

          read_client_messages(io) do |msg|
            if msg['keys']
              begin
                qemu.write(Base64.strict_decode64(msg['keys']))
              rescue IOError
                warn "Qemu for #{@domain} disconnected during write"
                return
              end
            end

            if msg['cols'] && msg['rows'] && (msg['cols'] != @cols || msg['rows'] != @rows)
              @cols = msg['cols']
              @rows = msg['rows']

              @resize_queue << :resize
            end
          end
        end
      end
    end

    def read_client_messages(io)
      begin
        data = io.readpartial(16 * 1024)
      rescue IOError
        warn "Client for domain #{@domain} disconnected during read"
        @mutex.synchronize { @clients.delete(io) }
        return
      end

      lines = []

      @mutex.synchronize do
        ret = []
        @clients[io] << data

        while (i = @clients[io].index("\n"))
          lines << @clients[io][0..i]
          @clients[io] = @clients[io][i + 1..]
        end
      end

      lines.each do |line|
        begin
          json = JSON.parse(line)
        rescue JSON::ParserError
          warn 'Unable to parse JSON from client'
          next
        end

        yield(json)
      end
    end

    def run_resize
      loop do
        @resize_queue.pop
        @resize_queue.clear

        break if @stop

        if system('vmctexec', @domain, '--', 'stty', '-F', '/dev/console', 'cols', @cols.to_s, 'rows', @rows.to_s)
          warn "Resized console for #{@domain} to cols=#{@cols} rows=#{@rows}"
        else
          warn "Failed to resize console for #{@domain}"
        end

        sleep(1)
      end
    end
  end
end
