module VpsAdmindCtl::Commands
  class Status < VpsAdmindCtl::Command
    description "Show vpsAdmind's status"
    
    def options(opts, args)
      @opts = {
          :workers => false,
          :consoles => false,
          :header => true,
      }

      opts.on('-c', '--consoles', 'List exported consoles') do
        @opts[:consoles] = true
      end
      
      opts.on('-t', '--subtasks', 'List subtasks') do
        @opts[:subtasks] = true
      end

      opts.on('-w', '--workers', 'List workers') do
        @opts[:workers] = true
      end

      opts.on('-H', '--no-header', 'Suppress header row') do
        @opts[:header] = false
      end
    end
    
    def process
      if @opts[:workers]
        puts sprintf(
          '%-8s %-8s %-5s %-20.19s %-5s %-18.16s %-8s %s',
          'QUEUE', 'TRANS', 'VEID', 'HANDLER', 'TYPE', 'TIME', 'PID', 'STEP'
        ) if @opts[:header]

        @res[:queues].each do |name, queue|
          queue[:workers].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |w|
            puts sprintf('%-8s %-8d %-5d %-20.19s %-5d %-18.16s %-8s %s',
                         name,
                         w[1][:id],
                         w[0].to_s,
                         w[1][:handler],
                         w[1][:type],
                         w[1][:start] ? format_duration(Time.new.to_i - w[1][:start]) : '---',
                         w[1][:pid],
                         w[1][:step]
                 )
          end
        end
      end

      if @opts[:consoles]
        puts sprintf('%-5s %s', 'VEID', 'LISTENERS')  if @opts[:header]

        @res[:consoles].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |c|
          puts sprintf('%-5d %d', c[0].to_s, c[1])
        end
      end

      if @opts[:subtasks]
        puts sprintf('%-10s %-10s %-20s %s', 'CHAIN', 'PID', 'STATE', 'NAME') if @opts[:header]

        @res[:subprocesses].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |chain_tasks|
          chain_tasks[1].each do |task|
            info = process_info(task)
            puts sprintf(
                '%-10d %-10d %-20s %s',
                chain_tasks[0].to_s,
                task,
                info[:state],
                info[:name]
            )
          end
        end
      end

      unless @opts[:workers] || @opts[:consoles] || @opts[:subtasks]
        puts "   Version: #{@vpsadmind.version}"
        puts "     State: #{state}"
        puts "    Uptime: #{format_duration(Time.new.to_i - @res[:start_time])}"
        puts "  Consoles: #{@res[:export_console] ? @res[:consoles].size : 'disabled'}"
        puts "  Subtasks: #{@res[:subprocesses].inject(0) { |sum, v| sum + v[1].size }}"
        puts "Queue size: #{@res[:queue_size]}"
        puts "    Queues:"

        @res[:queues].each do |name, queue|
          puts sprintf(
              "    %10s  %d / %d (+%d) %s",
              name,
              queue[:workers].size,
              queue[:threads],
              queue[:urgent],
              !queue[:started] ? "opens in #{format_duration((@res[:start_time] + queue[:start_delay]) - Time.now.to_i)}" : ''
          )
        end
      end
    end

    def state
      if @res[:state][:run]
        if @res[:state][:pause]
          "running, going to pause after #{@res[:state][:pause]}"
        else
          'running'
        end

      elsif @res[:state][:status] == 0
        'paused'

      else
        "finishing, going to #{translate_exitstatus(@res[:state][:status])}"
      end
    end

    def translate_exitstatus(s)
      {
         100 => 'stop',
         150 => 'restart',
         200 => 'update',
      }[s]
    end

    def process_info(pid)
      ret = {}
      s = File.open("/proc/#{pid}/status").read
      
      ret[:name] = /^Name:([^\n]+)/.match(s)[1].strip
      ret[:state] = /^State:([^\n]+)/.match(s)[1].strip
      ret

    rescue Errno::ENOENT, NoMethodError => e
      {}
    end
  end
end
