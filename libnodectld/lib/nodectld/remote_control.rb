require 'json'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/version'
require 'nodectld/exceptions'
require 'socket'

module NodeCtld
  class RemoteControl
    RUNDIR = '/run/nodectl'.freeze
    SOCKET = File.join(RUNDIR, 'nodectld.sock')

    extend Utils::Compat
    include OsCtl::Lib::Utils::Log

    @@handlers = {}

    def self.register(klass, name)
      @@handlers[name] = class_from_name(klass)
    end

    def self.handlers
      @@handlers
    end

    def initialize(daemon)
      @daemon = daemon
    end

    def start
      @thread = Thread.new do
        FileUtils.mkdir_p(RUNDIR, mode: 0o700)
        FileUtils.rm_f(SOCKET)
        serv = UNIXServer.new(SOCKET)
        File.chmod(0o600, SOCKET)

        loop do
          if @stop
            serv.close
            break
          end

          handle_client(serv.accept)
        end
      end
    end

    def stop
      @stop = true
      @thread.join
    end

    def handle_client(sock)
      Thread.new do
        c = Client.new(sock, @daemon)
        c.communicate
      end
    end

    class Client
      def initialize(sock, daemon)
        @sock = sock
        @daemon = daemon
      end

      def communicate
        send_data({ version: NodeCtld::VERSION })

        buf = ''

        while (m = @sock.recv(1024))
          buf += m
          break if m.empty? || m.end_with?("\n")
        end

        parse(buf)
      rescue Errno::ECONNRESET
        # pass
      end

      def parse(data)
        begin
          req = JSON.parse(data, symbolize_names: true)
        rescue TypeError, JSON::ParserError
          return error('Syntax error')
        end

        cmd = RemoteControl.handlers[req[:command].to_sym]

        return error('Unsupported command') unless cmd

        executor = cmd.new(req[:params] || {}, @daemon)
        output = {}

        begin
          ret = executor.exec
        rescue SystemCommandFailed => e
          output[:cmd] = e.cmd
          output[:exitstatus] = e.rc
          output[:error] = e.output
          error(output)
        rescue RemoteCommandError => e
          error(e.message)
        else
          if ret[:ret] == :ok
            ok(ret[:output])

          else
            error(ret[:output])
          end
        end
      end

      def error(err)
        send_data({ status: :failed, error: err })
      end

      def ok(res)
        send_data({ status: :ok, response: res })
      end

      def send_data(data)
        @sock.puts(data.to_json)
      rescue Errno::EPIPE
        # ignore
      end
    end
  end
end
