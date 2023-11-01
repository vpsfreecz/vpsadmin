module NodeCtl
  class Commands::Status < Command::Remote
    cmd :status
    description "Show nodectld's status"

    include Utils

    def options(parser, args)
      opts.update({
        workers: false,
        consoles: false,
        header: true,
      })

      parser.on('-c', '--consoles', 'List exported consoles') do
        opts[:consoles] = true
      end

      parser.on('-r', '--reservations', 'List queue reservations') do
        opts[:reservations] = true
      end

      parser.on('-t', '--subtasks', 'List subtasks') do
        opts[:subtasks] = true
      end

      parser.on('-w', '--workers', 'List workers') do
        opts[:workers] = true
      end

      parser.on('-H', '--no-header', 'Suppress header row') do
        opts[:header] = false
      end
    end

    def process
      if opts[:workers]
        if opts[:header]
          if global_opts[:parsable]
            puts sprintf(
              '%-8s %-8s %-8s %-20.19s %-5s %8s  %12s %-18.16s %-8s %s',
              'QUEUE', 'CHAIN', 'TRANS', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'ETA', 'PID', 'STEP'
            )

          else
            puts sprintf(
              '%-8s %-8s %-8s %-20.19s %-5s %-18.16s %12s %-18.16s  %-8s %s',
              'QUEUE', 'CHAIN', 'TRANS', 'HANDLER', 'TYPE', 'TIME', 'PROGRESS', 'ETA', 'PID', 'STEP'
            )
          end
        end

        t = Time.now

        response[:queues].each do |name, queue|
          queue[:workers].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |w|

            eta = nil

            if w[1][:progress] && w[1][:start]
              begin
                rate = w[1][:progress][:current] / (t.to_i - w[1][:start])
                eta = (w[1][:progress][:total] - w[1][:progress][:current]) / rate

              rescue ZeroDivisionError
                eta = nil
              end
            end

            if global_opts[:parsable]
              puts sprintf(
                '%-8s %-8d %-8d %-20.19s %-5d %8d %12s %-20.19s %-8s %s',
                name,
                w[0].to_s,
                w[1][:id],
                w[1][:handler],
                w[1][:type],
                w[1][:start] ? (t.to_i - w[1][:start]).round : '-',
                w[1][:pid] || '-',
                w[1][:progress] ? format_progress(t, w[1][:progress]) : '-',
                eta ? eta : '-',
                w[1][:step]
              )

            else
              puts sprintf(
                '%-8s %-8d %-8d %-20.19s %-5d %-18.16s %12s %-20.19s  %-8s  %s',
                name,
                w[0].to_s,
                w[1][:id],
                w[1][:handler],
                w[1][:type],
                w[1][:start] ? format_duration(t.to_i - w[1][:start]) : '-',
                w[1][:progress] ? format_progress(t, w[1][:progress]) : '-',
                eta ? format_duration(eta) : '-',
                w[1][:pid],
                w[1][:step]
              )
            end
          end
        end
      end

      if opts[:consoles]
        puts sprintf('%-5s %s', 'VEID', 'LISTENERS') if opts[:header]

        response[:consoles].sort { |a, b| a[0].to_s.to_i <=> b[0].to_s.to_i }.each do |c|
          puts sprintf('%-5d %d', c[0].to_s, c[1])
        end
      end

      if opts[:reservations]
        puts sprintf('%-12s %-10s', 'QUEUE', 'CHAIN')

        response[:queues].each do |name, queue|
          queue[:reservations].each do |r|
            puts sprintf("%-12s %-10d", name, r)
          end
        end
      end

      if opts[:subtasks]
        puts sprintf('%-10s %-10s %-20s %s', 'CHAIN', 'PID', 'STATE', 'NAME') if @opts[:header]

        response[:subprocesses].sort do |a, b|
          a[0].to_s.to_i <=> b[0].to_s.to_i

        end.each do |chain_tasks|
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

      unless opts[:workers] || opts[:consoles] || opts[:subtasks] || opts[:reservations]
        puts "   Version: #{client.version}"
        puts "     State: #{state}"
        puts "    Uptime: #{format_duration(Time.new.to_i - response[:start_time])}"
        puts "  Consoles: #{response[:export_console] ? response[:consoles].size : 'disabled'}"
        puts "  Subtasks: #{response[:subprocesses].inject(0) { |sum, v| sum + v[1].size }}"
        puts "Queue size: #{response[:queue_size]}"
        puts "    Queues:"

        response[:queues].each do |name, queue|
          puts sprintf(
            "    %10s  %d / %d (+%d%s) %s",
            name,
            queue[:workers].size,
            queue[:threads],
            queue[:urgent],
            queue[:reservations].empty? ? '' : " *#{queue[:reservations].size}",
            format_queue_state(queue),
          )
        end
      end

      ok
    end

    def format_queue_state(queue)
      if !queue[:open]
        if queue[:start_delay] > 0
          "paused for #{format_queue_start_delay(queue)}"
        else
          "paused"
        end
      elsif !queue[:started]
        "opens in #{format_queue_start_delay(queue)}"
      else
        ''
      end
    end

    def format_queue_start_delay(queue)
      format_duration((response[:start_time] + queue[:start_delay]) - Time.now.to_i)
    end

    def state
      if !response[:state][:initialized]
        'initializing'

      elsif response[:state][:run]
        if response[:state][:pause]
          "running, going to pause after #{response[:state][:pause]}"
        else
          'running'
        end

      elsif response[:state][:status] == 0
        'paused'

      else
        "finishing, going to #{translate_exitstatus(response[:state][:status])}"
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
