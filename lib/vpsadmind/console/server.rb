require 'rubygems'
require 'eventmachine'
require 'pry'

module VpsAdmind  
  class Console::Server < EventMachine::Connection
    include Utils::Log

    def receive_data(raw_data)
      raw_data.split("\n").each do |msg|
        process_msg(JSON.parse(msg, :symbolize_names => true))
      end

    rescue JSON::ParserError
      fatal_error('unable to parse data as JSON')
      puts raw_data
    end

    def unbind
      detach_console if !@detached && @console
    end

    def detach_console
      @detached = true

      @console.usage -= 1

      if @console.usage == 0
        Console::Wrapper.consoles do |c|
          c[@veid].send_cmd('Q')
          c.delete(@veid)
        end
      end
    end

    def console_detached
      @detached = true
      send_data("The console has been detached.\r\n")
      close_connection_after_writing
    end

    protected
    def process_msg(data)
      if data[:width] && data[:height]
        @w ||= data[:width]
        @h ||= data[:height]
      end

      unless @veid
        init = true
        return unless open_console(data)
      end

      Console::Wrapper.consoles do |c|
        if !data[:keys].nil? && !data[:keys].empty?
          c[@veid].send_cmd('W', data[:keys])
        end

        if (data[:width] && data[:height]) && \
            (@w != data[:width] || @h != data[:height] || init)
          c[@veid].send_cmd('S', "#{data[:width]} #{data[:height]}")
        end
      end
    end
    
    def open_console(data)
      db = Db.new
      st = db.prepared_st(
          'SELECT vps_id FROM vps_console WHERE token = ? AND expiration > ?',
          data[:session], # can be nil
          Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      )

      if st.num_rows == 1
        @veid = st.fetch[0].to_i

      else
        db.close
        fatal_error("Invalid session token\r\n")
        return false
      end

      db.close

      Console::Wrapper.consoles do |c|
        if c.include?(@veid)
          @console = c[@veid]
          @console.register(self)

        else
          log(:info, :console, "Attaching console of ##{@veid}")
          @console = EventMachine.popen(
              File.join(
                  File.dirname(__FILE__),
                  '..',
                  '..',
                  '..',
                  'bin',
                  'vpsadmind-vps-console'
              ) + " '#{$CFG.get(:vz, :vzctl)}' #{@veid}",
              Console::Wrapper, @veid, self
          )
        end
      end

      send_data("Welcome to vpsFree.cz Remote Console\r\n")
      true

    rescue => e
      fatal_error("Failed to attach console, sorry.\r\n")
      false
    end

    def fatal_error(msg)
      log(:warn, :console, msg)
      send_data("Failed to attach console, sorry.\r\n")
      close_connection_after_writing
    end
  end
end
