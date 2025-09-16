require 'json'

module ConsoleServer
  class Consoles
    class ConsoleExists < StandardError; end

    class ConsoleNotFound < StandardError; end

    def initialize(state_dir)
      @state_file = File.join(state_dir, 'consoles.json')
      @servers = load_state
      @mutex = Mutex.new

      @servers.each_value(&:start)
    end

    def start(domain, port)
      @mutex.synchronize do
        if @servers.has_key?(domain)
          if @servers[domain].port != port
            raise ConsoleExists,
                  "Server for #{domain} already exists with port #{@servers[domain].port}"
          end

          next
        end

        @servers[domain] = Server.new(domain, port)
        save_state
        @servers[domain].start
      end
    end

    def stop(domain)
      @mutex.synchronize do
        srv = @servers.delete(domain)
        next if srv.nil?

        save_state
        srv.stop
      end
    end

    def attach(domain, client)
      @mutex.synchronize do
        srv = @servers[domain]
        raise ConsoleNotFound, "Console for #{domain} not found" if srv.nil?

        srv.attach(client)
      end
    end

    protected

    def save_state
      tmp = "#{@state_file}.new"
      state = {
        servers: @servers.map { |_, s| { domain: s.domain, port: s.port } }
      }

      File.write(tmp, JSON.pretty_generate(state))
      File.rename(tmp, @state_file)
    end

    def load_state
      begin
        str = File.read(@state_file)
      rescue Errno::ENOENT
        return {}
      end

      json = JSON.parse(str)

      json.fetch('servers', []).to_h do |s|
        [s['domain'], Server.new(s['domain'], s['port'])]
      end
    end
  end
end
