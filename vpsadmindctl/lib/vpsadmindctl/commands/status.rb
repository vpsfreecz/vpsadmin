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
              '%-8s %-8s %-20.19s %-5s %8s  %12s %-18.16s %-8s %s',
              'TRANS', 'CMD', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'ETA', 'PID', 'STEP'
            )

          else
            puts sprintf(
              '%-8s %-8s %-20.19s %-5s %-18.16s %12s %-18.16s  %-8s %s',
              'TRANS', 'CMD', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'ETA', 'PID', 'STEP'
            )
          end
        end

        t = Time.now

        @res[:workers].each do |cmd|
          eta = nil

          if cmd[:progress] && cmd[:start]
            begin
              rate = cmd[:progress][:current] / (t.to_i - cmd[:start])
              eta = (cmd[:progress][:total] - cmd[:progress][:current]) / rate

            rescue ZeroDivisionError
              eta = nil
            end
          end

          if @global_opts[:parsable]
            puts sprintf(
              '%-8d %-8d %-20.19s %-5d %8d %12s %-20.19s %-8s %s',
              cmd[:transaction_id],
              cmd[:command_id],
              cmd[:handler],
              cmd[:handle],
              cmd[:start] ? (t.to_i - cmd[:start]).round : '-',
              cmd[:pid] || '-',
              cmd[:progress] ? format_progress(t, cmd[:progress]) : '-',
              eta ? eta : '-',
              cmd[:step]
            )

          else
            puts sprintf(
              '%-8d %-8d %-20.19s %-5d %-18.16s %12s %-20.19s  %-8s  %s',
              cmd[:transaction_id],
              cmd[:command_id],
              cmd[:handler],
              cmd[:handle],
              cmd[:start] ? format_duration(t.to_i - cmd[:start]) : '-',
              cmd[:progress] ? format_progress(t, cmd[:progress]) : '-',
              eta ? format_duration(eta) : '-',
              cmd[:pid],
              cmd[:step]
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
        puts "   Workers: #{@res[:workers].count}"
      end
    end

    def state
      if @res[:state][:pause]
        'paused'

      elsif @res[:state][:run]
        'running'

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
