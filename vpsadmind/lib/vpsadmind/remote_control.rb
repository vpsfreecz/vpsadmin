require 'etc'

module VpsAdmind
  class RemoteControl
    include Utils::Log

    NODE_USER_NAME = 'node'
    NODE_USER_UID = Etc.getpwnam(NODE_USER_NAME).uid

    @@handlers = {}

    def self.register(name, klass)
      @@handlers[name] = klass
    end

    def self.handlers
      @@handlers
    end

    def initialize(daemon)
      @daemon = daemon
    end

    def start
      @thread = Thread.new do
        path = $CFG.get(:remote, :socket)
        File.unlink(path) if File.exists?(path)
        serv = UNIXServer.new(path)
        File.chown(NODE_USER_UID, 0, path)

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
        send_data({:version => VpsAdmind::VERSION})

        buf = ""

        while m = @sock.recv(1024)
          buf = buf + m
          break if m.empty? || m.end_with?("\n")
        end

        parse(buf)

      rescue Errno::ECONNRESET
        # pass
      end

      def parse(data)
        begin
          req = JSON.parse(data, :symbolize_names => true)

        rescue TypeError, JSON::ParserError
          return error("Syntax error")
        end

        cmd = RemoteControl.handlers[ req[:command].to_sym ]

        return error("Unsupported command") unless cmd

        executor = cmd.new(req[:params] || {}, @daemon)
        output = {}

        begin
          ret = executor.exec

        rescue SystemCommandFailed => err
          output[:cmd] = err.cmd
          output[:exitstatus] = err.rc
          output[:error] = err.output
          error(output)

        else
          if ret[:ret] == :ok
            ok(ret[:output])

          else
            error(ret[:output])
          end
        end
      end

      def error(err)
        send_data({:status => :failed, :response => err})
      end

      def ok(res)
        send_data({:status => :ok, :response => res})
      end

      def send_data(data)
        @sock.send(data.to_json + "\n", 0)

      rescue Errno::EPIPE
      end
    end
  end
end
