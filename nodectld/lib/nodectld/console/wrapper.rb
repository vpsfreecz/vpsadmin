require 'libosctl'
require 'monitor'

module NodeCtld
  class Console::Wrapper < EventMachine::Connection
    include OsCtl::Lib::Utils::Log

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
      log(
        :info,
        :console,
        "Detached console of ##{@veid} with exit status: #{get_status.exitstatus}"
      )

      @listeners.each do |l|
        l.console_detached
      end

      @@mutex.synchronize do
        @@consoles.delete(@veid)
      end
    end

    def register(c)
      @listeners << c
      @usage += 1
    end

    def self.consoles
      @@mutex.synchronize do
        yield(@@consoles)
      end
    end
  end
end
