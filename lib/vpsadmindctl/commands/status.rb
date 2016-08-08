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
      
      opts.on('-m', '--mounts', 'List delayed mounts') do
        @opts[:mounts] = true
      end
      
      opts.on('-r', '--reservations', 'List queue reservations') do
        @opts[:reservations] = true
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
        if @opts[:header]
          if @global_opts[:parsable]
            puts sprintf(
              '%-8s %-8s %-8s %-20.19s %-5s %8s  %12s %-8s %s',
              'QUEUE', 'CHAIN', 'TRANS', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'PID', 'STEP'
            )

          else
            puts sprintf(
              '%-8s %-8s %-8s %-20.19s %-5s %-18.16s %12s  %-8s %s',
              'QUEUE', 'CHAIN', 'TRANS', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'PID', 'STEP'
            )
          end
        end

        t = Time.now

        @res[:queues].each do |name, queue|
          queue[:workers].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |w|
            if @global_opts[:parsable]
              puts sprintf(
                  '%-8s %-8d %-8d %-20.19s %-5d %8d %12s %-8s %s',
                  name,
                  w[0].to_s,
                  w[1][:id],
                  w[1][:handler],
                  w[1][:type],
                  w[1][:start] ? (t.to_i - w[1][:start]).round : '-',
                  w[1][:pid] || '-',
                  w[1][:progress] ? format_progress(t, w[1][:progress]) : '-',
                  w[1][:step]
              )

            else
              puts sprintf(
                  '%-8s %-8d %-8d %-20.19s %-5d %-18.16s %12s  %-8s  %s',
                  name,
                  w[0].to_s,
                  w[1][:id],
                  w[1][:handler],
                  w[1][:type],
                  w[1][:start] ? format_duration(t.to_i - w[1][:start]) : '-',
                  w[1][:progress] ? format_progress(t, w[1][:progress]) : '-',
                  w[1][:pid],
                  w[1][:step]
              )
            end
          end
        end
      end

      if @opts[:consoles]
        puts sprintf('%-5s %s', 'VEID', 'LISTENERS')  if @opts[:header]

        @res[:consoles].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |c|
          puts sprintf('%-5d %d', c[0].to_s, c[1])
        end
      end

      if @opts[:reservations]
        puts sprintf('%-12s %-10s', 'QUEUE', 'CHAIN')

        @res[:queues].each do |name, queue|
          queue[:reservations].each do |r|
            puts sprintf("%-12s %-10d", name, r)
          end
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

      if @opts[:mounts]
        puts sprintf('%-5s %-6s %-16s %-18.16s %s', 'VEID', 'ID', 'TYPE', 'TIME', 'DST')

        @res[:delayed_mounts].sort do |a, b|
          a[0].to_s.to_i <=> b[0].to_s.to_i
        end.each do |vps_id, mounts|

          mounts.each do |m|
            puts sprintf(
                '%-5s %-6s %-16s %-18.16s %s',
                vps_id,
                m[:id],
                m[:type],
                format_duration(Time.new.to_i - m[:registered_at]),
                m[:dst]
            )
          end

        end
      end

      unless @opts[:workers] || @opts[:consoles] || @opts[:subtasks] \
            || @opts[:mounts] || @opts[:reservations]
        puts "   Version: #{@vpsadmind.version}"
        puts "     State: #{state}"
        puts "    Uptime: #{format_duration(Time.new.to_i - @res[:start_time])}"
        puts "  Consoles: #{@res[:export_console] ? @res[:consoles].size : 'disabled'}"
        puts "  Subtasks: #{@res[:subprocesses].inject(0) { |sum, v| sum + v[1].size }}"
        puts "    Mounts: #{@res[:delayed_mounts].inject(0) { |sum, v| sum + v[1].size }}"
        puts "Queue size: #{@res[:queue_size]}"
        puts "    Queues:"

        @res[:queues].each do |name, queue|
          puts sprintf(
              "    %10s  %d / %d (+%d%s) %s",
              name,
              queue[:workers].size,
              queue[:threads],
              queue[:urgent],
              queue[:reservations].empty? ? '' : " *#{queue[:reservations].size}",
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
