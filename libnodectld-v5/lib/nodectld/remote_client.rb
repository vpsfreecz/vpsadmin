require 'json'
require 'socket'

module NodeCtld
  class RemoteClient
    class << self
      def send(sock, cmd, params = {})
        i = new(sock)
        i.open
        i.cmd(cmd, params)
        i.reply
      end

      def send_or_not(sock, cmd, params = {})
        i = new(sock)
        i.open
        i.cmd(cmd, params)
        i.close
      rescue StandardError
        # nothing to do
      end
    end

    def initialize(sock)
      @sock_path = sock
    end

    def open
      @sock = UNIXSocket.new(@sock_path)
      greetings = reply
      @version = greetings[:version]
    end

    def cmd(cmd, params = {})
      @sock.puts({ command: cmd, params: }.to_json)
    end

    def reply
      buf = ''

      while (m = @sock.recv(1024))
        buf += m
        break if m[-1].chr == "\n"
      end

      parse(buf)
    end

    def response
      reply[:response]
    end

    def close
      @sock.close
    end

    def parse(raw)
      JSON.parse(raw, symbolize_names: true)
    end
  end
end
