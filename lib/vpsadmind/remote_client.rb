module VpsAdmind
  class RemoteClient
    class << self
      def send(sock, cmd, params = {})
        i = new(sock)
        i.open
        i.cmd(cmd, params)
        i.reply
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
      @sock.send({:command => cmd, :params => params}.to_json + "\n", 0)
    end

    def reply
      buf = ""

      while m = @sock.recv(1024)
        buf = buf + m
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
      JSON.parse(raw, :symbolize_names => true)
    end
  end
end
