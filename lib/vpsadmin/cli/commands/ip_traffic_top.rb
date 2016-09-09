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
          params: %i(bytes_in bytes_out bytes),
          unit: :bits,
          order: '-bytes',
      }

      opts.on('-o', '--parameters PARAMS', 'Output parameters to show, separated by comma') do |v|
        @opts[:params] = v.split(',').map(&:to_sym)
      end

      opts.on('--unit UNIT', %w(bytes bits), 'Select data unit (bytes or bits)') do |v|
        @opts[:unit] = v.to_sym
      end

      opts.on('--order PARAM', 'Order by specified output parameter') do |v|
        @opts[:order] = v
      end
    end

    def exec(args)
      init_screen
      start_color
      crmode
      self.timeout = REFRESH_RATE * 1000

      init_pair(1, COLOR_BLACK, COLOR_WHITE)

      loop do
        render

        break if getch == 'q'
      end

    rescue Interrupt
    ensure
      close_screen
    end

    protected
    def fetch
      @api.ip_traffic_monitor.list(
          order: @opts[:order],
          meta: {includes: 'ip_address'}
      )
    end

    def render
      t = Time.now

      setpos(0, 0)
      addstr("#{File.basename($0)} ip_traffic top - #{t.strftime('%H:%M:%S')}, ")
      addstr("next update at #{(t + REFRESH_RATE).strftime('%H:%M:%S')}, ")
      addstr("unit: #{@opts[:unit]} per second")
     
      fmt = "%-30s #{Array.new(@opts[:params].count, '%10s').join(' ')}"

      attron(color_pair(1))
      setpos(2, 0)

      header = sprintf(
          fmt,
          'IP Address',
          *param_titles,
      )
      addstr(header + (' ' * (cols - header.size)) + "\n")
      attroff(color_pair(1))

      i = 3
      fetch.each do |data|
        setpos(i, 0)
        addstr(sprintf(
            fmt,
            data.ip_address.addr,
            *param_values(data),
        ))

        i += 1
      end

      refresh
    end

    def param_titles
      @opts[:params].map do |v|
        v.to_s.split('_').map do |p|
          if @opts[:unit] == :bits
            p.gsub(/bytes/, 'bits').capitalize

          else
            p.capitalize
          end
        end.join('')
      end
    end

    def param_values(data)
      @opts[:params].map { |v| unitize(data.send(v), data.delta) }
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
  end
end
