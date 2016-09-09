require 'curses'

module VpsAdmin::CLI::Commands
  class IpTrafficTop < BackupDataset
    include Curses

    REFRESH_RATE = 10
    FILTERS = %i(limit ip_address ip_version environment location network ip_range node vps)

    cmd :ip_traffic, :top
    args ''
    desc 'Live IP traffic monitor'
    
    def options(opts)
      @opts = {
          unit: :bits,
      }

      opts.on('--unit UNIT', %w(bytes bits), 'Select data unit (bytes or bits)') do |v|
        @opts[:unit] = v.to_sym
      end
      
      opts.on('--limit LIMIT', Integer, 'Number of IP addresses to monitor') do |v|
        @opts[:limit] = v
      end
      
      opts.on('--ip-address ID', Integer, 'ID of IP addresses to monitor') do |v|
        @opts[:ip_address] = v
      end
      
      opts.on('--ip-version VER', [4, 6], 'Filter IP addresses by version') do |v|
        @opts[:ip_version] = v
      end
    
      (FILTERS - %i(limit ip_address ip_version)).each do |f|
        opts.on("--#{f.to_s.gsub(/_/, '-')} ID", Integer, "Filter IP addresses by #{f}") do |v|
          @opts[f] = v
        end
      end
    end

    def exec(args)
      set_global_opts
      init_screen
      start_color
      crmode
      stdscr.keypad = true
      curs_set(0)  # hide cursor

      init_pair(1, COLOR_BLACK, COLOR_WHITE)
      last = nil

      loop do
        now = Time.now

        if @refresh || last.nil? || (now - last) >= REFRESH_RATE
          @refresh = false
          render(now, true)
          last = Time.now
          self.timeout = REFRESH_RATE * 1000

        else
          render(last, false)
          self.timeout = (REFRESH_RATE - (now - last)) * 1000
        end

        case getch
        when 'q'
          break

        when Key::LEFT
          sort_next(-1)

        when Key::RIGHT
          sort_next(+1)

        when Key::UP, Key::DOWN
          sort_inverse
        end
      end

    rescue Interrupt
    ensure
      close_screen
    end

    protected
    def set_global_opts
      if @global_opts[:output]
        @params = @global_opts[:output].split(',').map(&:to_sym)

      else
        @params = %i(bytes_in bytes_out bytes)
      end

      if @global_opts[:sort]
        v = @global_opts[:sort]
        @sort_desc = v.start_with?('-')
        @sort_param = (v.start_with?('-') ? v[1..-1] : v).to_sym

      else
        @sort_desc = true
        @sort_param = :bytes
      end

      @columns = []

      @params.each do |p|
        title = p.to_s.split('_').map do |v|
          if @opts[:unit] == :bits
            v.to_s.gsub(/bytes/, 'bits').capitalize

          else
            v.capitalize
          end
        end.join('')

        size = title.size + 1

        @columns << {
            name: p,
            title: title,
            width: size < 8 ? 8 : size,
        }
      end
    end

    def fetch
      return @data if @data

      params =  {
          order: "#{@sort_desc ? '-' : ''}#{@sort_param}",
          meta: {includes: 'ip_address'}
      }

      FILTERS.each do |f|
        next unless @opts[f]

        params[f] = @opts[f]
      end

      @data = @api.ip_traffic_monitor.list(params)
    end

    def render(t, refresh)
      if refresh
        @data = nil
        @header = nil
      end

      setpos(0, 0)
      addstr("#{File.basename($0)} ip_traffic top - #{t.strftime('%H:%M:%S')}, ")
      addstr("next update at #{(t + REFRESH_RATE).strftime('%H:%M:%S')}, ")
      addstr("unit: #{@opts[:unit]} per second")

      attron(color_pair(1))
      setpos(2, 0)
      header
      attroff(color_pair(1))

      i = 3
      
      fetch.each do |data|
        setpos(i, 0)
        print_row(data)
        
        i += 1

        break if i >= (lines - 5)
      end

      stats
      refresh
    end

    def header
      unless @header
        fmt = (['%-30s'] + @columns.map { |c| "%#{c[:width]}s" }).join(' ')

        @header = sprintf(
            fmt,
            'IP Address',
            *@columns.map { |c| c[:title] },
        )

        @header << (' ' * (cols - @header.size)) << "\n"
      end
      
      addstr(@header)
    end

    def print_row(data)
      addstr(sprintf('%-30s', data.ip_address.addr))

      @columns.each do |c|
        p = c[:name]

        attron(A_BOLD) if p == @sort_param
        addstr(sprintf(" %#{c[:width]}s", unitize(data.send(p), data.delta)))
        attroff(A_BOLD) if p == @sort_param
      end
    end

    def stats
      fields = %i(packets bytes public_bytes private_bytes)
      stats = {}
      delta_sum = 0

      fields.each do |f|
        stats[f] = 0
        
        %i(in out).each do |dir|
          stats[:"#{f}_#{dir}"] = 0
        end
      end

      fetch.each do |data|
        delta_sum += data.delta

        fields.each do |f|
          stats[f] += data.send(f)
          
          %i(in out).each do |dir|
            stats[:"#{f}_#{dir}"] += data.send("#{f}_#{dir}")
          end
        end
      end

      avg_delta = delta_sum.to_f / fetch.count

      setpos(lines-5, 0)
      addstr('─' * cols)

      fmt = Array.new(5, '%10s').join(' ')

      setpos(lines-4, 0)
      addstr(sprintf(fmt, '', 'Packets', @opts[:unit].to_s.capitalize, 'Public', 'Private'))

      setpos(lines-3, 0)
      addstr(sprintf(fmt, 'In', *fields.map { |f| unitize(stats[:"#{f}_in"], avg_delta) }))
      
      setpos(lines-2, 0)
      addstr(sprintf(fmt, 'Out', *fields.map { |f| unitize(stats[:"#{f}_out"], avg_delta) }))
      
      setpos(lines-1, 0)
      addstr(sprintf(fmt, 'Total', *fields.map { |f| unitize(stats[:"#{f}_in"] + stats[:"#{f}_out"], avg_delta) }))
    end

    def unitize(n, delta)
      if @opts[:unit] == :bytes
        per_s = n / delta.to_f
      else
        per_s = n * 8 / delta.to_f
      end

      bits = 39
      units = %i(T G M K)

      units.each do |u|
        threshold = 2 << bits

        return "#{(per_s / threshold).round(2)}#{u}" if per_s >= threshold

        bits -= 10
      end

      per_s.to_s
    end

    def sort_next(n)
      cur_i = @params.index(@sort_param)
      next_i = cur_i + n
      return unless @params[next_i]

      @sort_param = @params[next_i]
      @refresh = true
    end

    def sort_inverse
      @sort_desc = !@sort_desc
      @refresh = true
    end
  end
end
