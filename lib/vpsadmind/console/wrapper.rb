require 'monitor'

module VpsAdmind
  class Console::Wrapper < EventMachine::Connection
    attr_accessor :usage

    @@consoles = {}
    @@mutex = Monitor.new

    def initialize(veid, listener)
      @veid = veid
      @listeners = [listener,]
      @usage = 1

      @@mutex.synchronize do
        @@consoles[@veid] = self
      end
    end

    def post_init
      send_data "\n"
    end

    def receive_data(data)
      @listeners.each do |l|
        l.send_data(data)
      end
    end

    def unbind
      puts "console detached with exit status: #{get_status.exitstatus}"
    end

    def register(c)
      @listeners << c
      @usage += 1
    end

    def send_cmd(cmd, arg = nil)
      msg = cmd
      msg += " #{arg}" if arg
      msg += "\n"

      send_data(msg)
    end

    def self.consoles
      @@mutex.synchronize do
        yield(@@consoles)
      end
    end
  end
end
