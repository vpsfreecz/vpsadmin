require 'curses'

module VpsAdmin::CLI::Commands
  class IpTrafficTop < BackupDataset
    include Curses

    REFRESH_RATE = 10

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

      @data = @api.ip_traffic_monitor.list(
          order: "#{@sort_desc ? '-' : ''}#{@sort_param}",
          meta: {includes: 'ip_address'}
      )
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
      end

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
