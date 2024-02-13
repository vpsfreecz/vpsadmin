require 'time'
require 'json'
require 'base64'
require 'io/wait'
require 'terminal_size'

module VpsAdmin::CLI::Commands
  class VpsRemoteControl < HaveAPI::CLI::Command
    cmd :vps, :remote_console
    args 'VPS_ID'
    desc 'Open VPS remote console'

    class InputHandler
      def initialize(http_client)
        @http_client = http_client
        @private_buffer = ''
        @end_seq = ["\r", "\e", '.']
        @end_i = 0
        @stop = false
      end

      def read_from(io)
        begin
          data = io.read_nonblock(4096)
        rescue IO::WaitReadable
          return
        rescue Errno::EIO
          stop
          return
        end

        write(data)
      end

      def stop?
        @stop
      end

      protected

      attr_reader :http_client

      # Data is checked on the presence of the end sequence. The first character
      # in the sequence (ENTER) can be read multiple times in a row and it is
      # to be forwarded.
      #
      # When the second character in the end sequence is read, it is not forwarded,
      # but stored in a private buffer. If the sequence is later broken, the private
      # buffer is forwarded and reset.
      #
      # If the whole end sequence is read, we exit.
      def write(data)
        buffer = ''

        data.each_char do |char|
          if char == @end_seq[@end_i]
            if @end_i == @end_seq.size - 1
              @stop = true
              return # rubocop:disable Lint/NonLocalExitFromIterator
            end

            @end_i += 1

            if @end_i == 1
              buffer += char
            else
              @private_buffer += char
            end

          elsif char == @end_seq.first
            buffer += char
          else
            @end_i = 0

            unless @private_buffer.empty?
              buffer += @private_buffer
              @private_buffer.clear
            end

            buffer += char
          end
        end

        http_client.write(buffer) unless buffer.empty?
      end
    end

    class HttpClient
      def initialize(vps, token, rate)
        @vps = vps
        @token = token
        @rate = rate
        @mutex = Mutex.new
        @write_buffer = ''
        @stop = false
        @error = false
      end

      def start
        @thread = Thread.new { run }
      end

      def stop
        @stop = true
      end

      def stop?
        @stop
      end

      def error?
        @error != false
      end

      attr_reader :error

      def join
        stop
        thread.join
      end

      def write(data)
        mutex.synchronize do
          write_buffer << data
        end
      end

      def resize(width, height)
        @width = width
        @height = height
      end

      protected

      attr_reader :vps, :token, :rate, :width, :height, :write_buffer,
                  :mutex, :thread

      def run
        uri = URI("#{vps.node.location.remote_console_server}/console/feed/#{vps.id}")
        start_args = [uri.host, uri.port, nil, nil, nil, nil, {
          use_ssl: uri.scheme == 'https'
        }]

        Net::HTTP.start(*start_args) do |http|
          loop do
            break if stop? || error?

            rate_limit { send_request(http, uri) }
          end
        end
      end

      def send_request(http, uri)
        req = Net::HTTP::Post.new(uri)

        keys =
          mutex.synchronize do
            s = write_buffer.dup
            write_buffer.clear
            s
          end

        req.set_form_data(
          'session' => token,
          'keys' => keys,
          'width' => width,
          'height' => height
        )

        res = http.request(req)

        unless res.is_a?(Net::HTTPSuccess)
          set_error(
            'Console server returned error: ' \
            "HTTP #{res.code} - #{res.message}\n\n#{res.body}"
          )
          stop
          return
        end

        ret = JSON.parse(res.body, symbolize_names: true)

        unless ret[:session]
          $stdout.write(ret[:data])
          set_error('Session closed.')
          stop
          return
        end

        $stdout.write(Base64.decode64(ret[:data]))
      end

      def rate_limit
        t1 = Time.now
        yield
        t2 = Time.now

        cooldown = rate - (t2 - t1)
        sleep(cooldown) if cooldown > 0
      end

      def set_error(str)
        @error = str
      end
    end

    def options(opts)
      @opts = {
        rate: 0.05
      }

      opts.on('--refresh-rate MSEC', 'How often send and receive data, defaults to 50 ms') do |r|
        @opts[:rate] = r.to_i / 1000.0
      end
    end

    def exec(args)
      if args.empty?
        puts 'provide VPS ID as an argument'
        exit(false)
      end

      vps_id = args.first.to_i

      write 'Locating VPS..'
      begin
        vps = @api.vps.show(vps_id, meta: { includes: 'node__location' })
      rescue HaveAPI::Client::ActionFailed => e
        puts '  error'
        puts e.message
        exit(false)
      end

      puts "  VPS is on #{vps.node.domain_name}, located in #{vps.node.location.label}."
      puts "Console server URL is #{vps.node.location.remote_console_server}"
      write 'Obtaining authentication token...'

      begin
        t = vps.console_token.create
      rescue HaveAPI::Client::ActionFailed => e
        puts '  error'
        puts e.message
        exit(false)
      end

      puts
      puts 'Connecting to the remote console...'
      puts 'Press ENTER ESC . to exit'
      puts

      raw_mode do
        run_console(vps, t.token)
      end
    end

    protected

    attr_reader :client

    def raw_mode
      state = `stty -g`
      `stty raw -echo -icanon -isig`

      pid = Process.fork do
        @size = Terminal.size!

        Signal.trap('WINCH') do
          @size = Terminal.size!
          client.resize(@size[:width], @size[:height]) if client
        end

        yield
      end

      Process.wait(pid)

      `stty #{state}`
      puts
    end

    def run_console(vps, token)
      Thread.abort_on_exception = true

      @client = HttpClient.new(vps, token, @opts[:rate])
      client.resize(@size[:width], @size[:height])

      input = InputHandler.new(client)
      client.start

      loop do
        res = $stdin.wait_readable(1)
        input.read_from($stdin) if res

        next unless input.stop? || client.stop?

        client.join

        if client.error?
          write("\n")
          write(client.error)
        end

        return
      end
    end

    def write(s)
      $stdout.write(s)
      $stdout.flush
    end
  end
end
