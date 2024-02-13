require 'socket'
require 'json'

module NodeCtl
  class Client
    attr_reader :version

    def initialize(sock)
      @sock_path = sock
    end

    def open
      @sock = UNIXSocket.new(@sock_path)
      greetings = receive
      @version = greetings[:version]
    end

    def cmd(cmd, params = {})
      @sock.send({ command: cmd, params: }.to_json + "\n", 0)
    end

    def receive
      buf = ''

      while m = @sock.recv(1024)
        buf += m
        break if m[-1].chr == "\n"
      end

      parse(buf)
    end

    def response
      receive[:response]
    end

    def close
      @sock.close
    end

    def parse(raw)
      JSON.parse(raw, symbolize_names: true)
    end
  end
end
