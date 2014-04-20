module Commands
  class Status < Command
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

      opts.on('-w', '--workers', 'List workers') do
        @opts[:workers] = true
      end

      opts.on('-H', '--no-header', 'Suppress columns header') do
        @opts[:header] = false
      end
    end
    
    def process
      if @opts[:workers]
        puts sprintf(
          '%-8s %-5s %-20.19s %-5s %-18.16s %-8s %s',
          'TRANS', 'VEID', 'HANDLER', 'TYPE', 'TIME', 'PID', 'STEP'
        ) if @opts[:header]

        @res[:workers].sort.each do |w|
          puts sprintf('%-8d %-5d %-20.19s %-5d %-18.16s %-8s %s',
                       w[1]['id'],
                       w[0],
                       w[1]['handler'],
                       w[1]['type'],
                       format_duration(Time.new.to_i - w[1]['start']),
                       w[1]['pid'],
                       w[1]['step']
               )
        end
      end

      if @opts[:consoles]
        puts sprintf('%-5s %s', 'VEID', 'LISTENERS')  if @opts[:header]

        @res[:consoles].sort.each do |c|
          puts sprintf('%-5d %d', c[0], c[1])
        end
      end

      unless @opts[:workers] || @opts[:consoles]
        puts "Version: #{@vpsadmind.version}"
        puts "Uptime: #{format_duration(Time.new.to_i - @res[:start_time])}"
        puts "Workers: #{@res[:workers].size}/#{@res[:threads]}"
        puts "Queue size: #{@res[:queue_size]}"
        puts "Exported consoles: #{@res[:export_console] ? @res[:consoles].size : 'disabled'}"
      end
    end
  end
end
