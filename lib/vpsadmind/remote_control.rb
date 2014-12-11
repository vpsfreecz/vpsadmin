module VpsAdmind
  class RemoteControl < EventMachine::Connection
    extend Utils::Compat
    extend Utils::Log

    @@handlers = {}

    def self.register(klass, name)
      @@handlers[name] = class_from_name(klass)
      log "Remote cmd #{name} => #{klass}"
    end

    def initialize(daemon)
      @daemon = daemon
    end

    def post_init
      send_data({:version => VpsAdmind::VERSION}.to_json + "\n")
    end

    def receive_data(data)
      begin
        req = JSON.parse(data, :symbolize_names => true)
      rescue TypeError
        return error("Syntax error")
      end

      cmd = @@handlers[ req[:command].to_sym ]

      return error("Unsupported command") unless cmd

      executor = cmd.new(req[:params] || {}, @daemon)
      output = {}

      begin
        ret = executor.exec
      rescue CommandFailed => err
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

    def unbind

    end

    def error(err)
      send_data({:status => :failed, :error => err}.to_json + "\n")
    end

    def ok(res)
      send_data({:status => :ok, :response => res}.to_json + "\n")
    end
  end
end
