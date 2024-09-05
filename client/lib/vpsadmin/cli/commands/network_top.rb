require 'curses'

module VpsAdmin::CLI::Commands
  class NetworkTop < HaveAPI::CLI::Command
    include Curses

    REFRESH_RATE = 10
    FILTERS = %i[limit user environment location node vps network_interface].freeze

    cmd :network, :top
    args ''
    desc 'Live network traffic monitor'

    def options(opts)
      @opts = {
        unit: :bits
      }

      opts.on('--unit UNIT', %w[bytes bits], 'Select data unit (bytes or bits)') do |v|
        @opts[:unit] = v.to_sym
      end

      opts.on('--limit LIMIT', Integer, 'Number of IP addresses to monitor') do |v|
        @opts[:limit] = v
      end

      (FILTERS - %i[limit]).each do |f|
        opts.on("--#{f.to_s.gsub('_', '-')} ID", Integer, "Filter network interfaces by #{f}") do |v|
          @opts[f] = v
        end
      end
    end

    def exec(_args)
      if @global_opts[:list_output]
        exclude = %i[id network_interface updated_at delta]

        @api.network_interface_monitor.actions[:index].params.each_key do |name|
          next if exclude.include?(name)

          puts name
        end

        exit
      end

      set_global_opts
      init_screen
      start_color
      crmode
      stdscr.keypad = true
      curs_set(0) # hide cursor
      use_default_colors

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
          clear
          sort_next(-1)

        when Key::RIGHT
          clear
          sort_next(+1)

        when Key::UP, Key::DOWN
          clear
          sort_inverse

        when Key::RESIZE
          clear
        end
      end
    rescue Interrupt
      # break loop and exit
    ensure
      close_screen
    end

    protected

    def set_global_opts
      @params = if @global_opts[:output]
                  @global_opts[:output].split(',').map(&:to_sym)
                else
                  %i[bytes bytes_in bytes_out packets packets_in packets_out]
                end

      if @global_opts[:sort]
        sort_v = @global_opts[:sort]
        @sort_desc = sort_v.start_with?('-')
        @sort_param = (sort_v.start_with?('-') ? sort_v[1..] : sort_v).to_sym

      else
        @sort_desc = true
        @sort_param = :bytes
      end

      @columns = []

      @params.each do |p|
        title = p.to_s.split('_').map do |v|
          if @opts[:unit] == :bits
            v.to_s.gsub('bytes', 'bits').capitalize

          else
            v.capitalize
          end
        end.join

        title << '/s'

        size = title.size + 1

        @columns << {
          name: p,
          title: title,
          width: [size, 8].max
        }
      end
    end

    def fetch
      return @data if @data

      limit = @opts[:limit] || (lines - 6)

      params = {
        limit: limit > 0 ? limit : 25,
        order: "#{@sort_desc ? '-' : ''}#{@sort_param}",
        meta: { includes: 'network_interface' }
      }

      FILTERS.each do |f|
        next unless @opts[f]

        params[f] = @opts[f]
      end

      @data = @api.network_interface_monitor.list(params)
    end

    def render(t, refresh)
      if refresh
        @data = nil
        @header = nil
      end

      setpos(0, 0)
      addstr("#{File.basename($0)} network top - #{t.strftime('%H:%M:%S')}, ")
      addstr("next update at #{(t + REFRESH_RATE).strftime('%H:%M:%S')}")

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
        fmt = (['%8s', '%-15s'] + @columns.map { |c| "%#{c[:width]}s" }).join(' ')

        @header = format(
          fmt,
          'VPS',
          'Interface',
          *@columns.map { |c| c[:title] }
        )

        @header << (' ' * (cols - @header.size)) << "\n"
      end

      addstr(@header)
    end

    def print_row(data)
      addstr(format(
               '%8s %-15s',
               data.network_interface.vps_id,
               data.network_interface.name
             ))

      @columns.each do |c|
        p = c[:name]

        attron(A_BOLD) if p == @sort_param
        addstr(format(" %#{c[:width]}s", unitize_param(p, data.send(p), data.delta)))
        attroff(A_BOLD) if p == @sort_param
      end
    end

    def stats
      fields = %i[bytes packets]
      stats = {}
      delta_sum = 0

      fields.each do |f|
        stats[f] = 0

        %i[in out].each do |dir|
          stats[:"#{f}_#{dir}"] = 0
        end
      end

      fetch.each do |data|
        delta_sum += data.delta

        fields.each do |f|
          stats[f] += data.send(f)

          %i[in out].each do |dir|
            stats[:"#{f}_#{dir}"] += data.send("#{f}_#{dir}")
          end
        end
      end

      avg_delta = delta_sum.to_f / fetch.count

      setpos(lines - 5, 0)
      addstr('─' * cols)

      fmt = '%10s %10s %10s'
      unit = @opts[:unit].to_s.capitalize

      setpos(lines - 4, 0)
      addstr(format(
               fmt,
               '',
               "#{unit}/s",
               'Packets/s'
             ))

      setpos(lines - 3, 0)
      addstr(format(fmt, 'In', *fields.map { |f| unitize_param(f, stats[:"#{f}_in"], avg_delta) }))

      setpos(lines - 2, 0)
      addstr(format(fmt, 'Out', *fields.map { |f| unitize_param(f, stats[:"#{f}_out"], avg_delta) }))

      setpos(lines - 1, 0)
      attron(A_BOLD)
      addstr(format(fmt, 'Total', *fields.map do |f|
                                    unitize_param(f, stats[:"#{f}_in"] + stats[:"#{f}_out"], avg_delta)
                                  end))
      attroff(A_BOLD)
    end

    def unitize_bytes(n, delta)
      per_s = if @opts[:unit] == :bytes
                n / delta.to_f
              else
                n * 8 / delta.to_f
              end

      bits = 39
      units = %w[T G M k]

      units.each do |u|
        threshold = 2 << bits

        return "#{(per_s / threshold).round(2)}#{u}" if per_s >= threshold

        bits -= 10
      end

      per_s.round(2).to_s
    end

    def unitize_number(n, delta)
      per_s = n / delta.to_f
      threshold = 1_000_000_000_000
      units = %w[T G M k]

      units.each do |u|
        return "#{(per_s / threshold).round(2)}#{u}" if per_s >= threshold

        threshold /= 1000
      end

      per_s.round(2).to_s
    end

    def unitize_param(param, n, delta)
      case param
      when :bytes, :bytes_in, :bytes_out
        unitize_bytes(n, delta)
      when :packets, :packets_in, :packets_out
        unitize_number(n, delta)
      else
        raise "unknown param to unitize: #{param.inspect}"
      end
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

    def ip_address_id(v)
      return v if /^\d+$/ =~ v

      ips = @api.ip_address.list(addr: v)
      return false if ips.count < 1

      ips.first.id
    rescue HaveAPI::Client::ActionFailed
      false
    end
  end
end
