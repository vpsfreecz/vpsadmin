require 'eventmachine'
require 'em-http'
require 'time'
require 'json'
require 'base64'
require 'terminal-size'

module VpsAdmin::CLI::Commands
  class VpsRemoteControl < HaveAPI::CLI::Command
    cmd :vps, :remote_console
    args 'VPS_ID'
    desc 'Open VPS remote console'

    class InputHandler < EventMachine::Connection
      attr_accessor :buffer

      def initialize
        @private_buffer = ''
        @buffer = ''
        @end_seq = ["\r", "\e", "."]
        @end_i = 0
      end

      # Data is checked on the presence of the end sequence. The first character
      # in the sequence (ENTER) can be read multiple times in a row and it is
      # to be forwarded.
      #
      # When the second character in the end sequence is read, it is not forwarded,
      # but stored in a private buffer. If the sequence is later broken, the private
      # buffer is forwarded and reset.
      #
      # If the whole end sequence is read, EM event loop is stopped.
      def receive_data(data)
        data.each_char do |char|
          if char == @end_seq[ @end_i ]
            if @end_i == @end_seq.size-1
              EM.stop
              return
            end

            @end_i += 1

            if @end_i == 1
              @buffer += char

            else
              @private_buffer += char
            end

          elsif char == @end_seq.first
            @buffer += char

          else
            @end_i = 0

            unless @private_buffer.empty?
              @buffer += @private_buffer
              @private_buffer.clear
            end

            @buffer += char
          end
        end
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
        puts "provide VPS ID as an argument"
        exit(false)
      end

      vps_id = args.first.to_i

      write "Locating VPS.."
      begin
        vps = @api.vps.show(vps_id, meta: { includes: 'node__location' })

      rescue HaveAPI::Client::ActionFailed => e
        puts "  error"
        puts e.message
        exit(false)
      end

      puts "  VPS is on #{vps.node.domain_name}, located in #{vps.node.location.label}."
      puts "Console router URL is #{vps.node.location.remote_console_server}"
      write "Obtaining authentication token..."

      begin
        t = vps.console_token.create

      rescue HaveAPI::Client::ActionFailed => e
        puts "  error"
        puts e.message
        exit(false)
      end

      @token = t.token

      puts
      puts "Connecting to remote console..."
      puts "Press ENTER ESC . to exit"
      puts

      raw_mode do
        EventMachine.run do
          @input = EventMachine.open_keyboard(InputHandler)

          @http = EventMachine::HttpRequest.new(
              "#{vps.node.location.remote_console_server}/console/feed/#{vps_id}"
          )
          communicate
        end
      end
    end

    protected
    def write(s)
      $stdout.write(s)
      $stdout.flush
    end

    def raw_mode
      state = `stty -g`
      `stty raw -echo -icanon -isig`

      pid = Process.fork do
        @size = Terminal.size!
        
        Signal.trap('WINCH') do
          @size = Terminal.size!
        end

        yield
      end

      Process.wait(pid) 

      `stty #{state}`
      puts
    end

    def communicate
      post = @http.post(
          body: {
              session: @token,
              keys: @input.buffer,
              width: @size[:width],
              height: @size[:height],
          },
          keepalive: true
      )

      @input.buffer = ''

      post.errback do
        puts "Error: connection to console router failed"
        EventMachine.stop
      end

      post.callback do
        ret = JSON.parse(post.response, symbolize_names: true)
        
        unless ret[:session]
          $stdout.write(ret[:data])
          puts "\nSession closed."
          EM.stop
          next
        end

        $stdout.write(Base64.decode64(ret[:data]))

        EM.add_timer(@opts[:rate]) { communicate }
      end
    end
  end
end
