require 'monitor'

require 'rubygems'
require 'eventmachine'

module VpsAdmind
  class VzConsole < EventMachine::Connection
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

      @listeners.each do |l|
        l.failed_to_attach
      end
    end

    def register(c)
      @listeners << c
      @usage += 1
    end

    def VzConsole.consoles
      @@mutex.synchronize do
        yield(@@consoles)
      end
    end
  end

  class VzServer < EventMachine::Connection
    def post_init

    end

    def receive_data(data)
      unless @veid
        begin
          lines = data.split
          @veid = lines[0].strip.to_i

          VzConsole.consoles do |c|
            if c.include?(@veid)
              @console = c[@veid]
              @console.register(self)
            else
              @console = EventMachine.popen("#{$CFG.get(:vz, :vzctl)} console #{@veid}", VzConsole, @veid, self)
            end
          end

          send_data("Welcome to vpsFree.cz Remote Console\r\n")
          data = lines[1..-1].join('\r\n')
        rescue
          return failed_to_attach
        end
      end

      return unless data

      if data.strip == "detach"
        send_data("See you later!\r\n")

        detach

        close_connection_after_writing
      else
        VzConsole.consoles do |c|
          c[@veid].send_data(data)
        end
      end
    end

    def unbind
      detach if !@detached && @console
    end

    def failed_to_attach
      send_data("Failed to attach console, sorry.\r\n")
      close_connection_after_writing
    end

    def detach
      @detached = true

      @console.usage -= 1

      if @console.usage == 0
        VzConsole.consoles do |c|
          c[@veid].send_data(13.chr)
          c[@veid].send_data(27.chr)
          c[@veid].send_data(".")
          c.delete(@veid)
        end
      end
    end
  end
end
