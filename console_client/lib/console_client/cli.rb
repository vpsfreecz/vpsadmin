require 'base64'
require 'console_client'
require 'io/console'
require 'json'
require 'optparse'
require 'socket'

module ConsoleClient
  class Cli
    def self.run
      new.run
    end

    def run
      options, args = parse_options

      command = args[0]
      params = { command: }

      case args[0]
      when 'start'
        if args.length != 3
          warn "Usage: #{$0} start <domain> <port>"
          exit(false)
        end

        params[:domain] = args[1]
        params[:port] = args[2]
      when 'stop', 'attach'
        if args.length != 2
          warn "Usage: #{$0} #{args[0]} <domain>"
          exit(false)
        end

        params[:domain] = args[1]
      end

      sock = UNIXSocket.new(options[:socket])
      sock.puts(params.to_json)

      resp = JSON.parse(sock.readline)
      raise "Error: #{resp['error']}" unless resp['status']

      return if %w[start stop].include?(command)

      if options[:json]
        attach_console_raw(sock)
      else
        attach_console_tty(sock)
      end
    end

    protected

    def parse_options
      options = {
        socket: '/run/console-server/control.sock',
        json: false
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options] <command> [arguments...]"

        opts.on('-s', '--socket PATH', 'Path to console server control socket') do |v|
          options[:socket] = v
        end

        opts.on('-j', '--json', 'Send JSON commands to the console server') do
          options[:json] = true
        end
      end

      args = parser.parse!

      if args.empty?
        warn parser
        exit(false)
      end

      [options, args]
    end

    def attach_console_tty(sock)
      puts 'Press Ctrl+a q to detach the console'
      puts

      state = `stty -g`
      `stty raw -echo -icanon -isig`

      pid = Process.fork do
        console = Console.new(sock, $stdin, $stdout)

        Signal.trap('WINCH') do
          console.resize(*$stdin.winsize)
        end

        console.open
      end

      Process.wait(pid)

      `stty #{state}`
      puts
    end

    def attach_console_raw(sock)
      console = Console.new(sock, $stdin, $stdout, raw: true)

      Signal.trap('TERM') do
        console.close
      end

      console.open
    end
  end
end
