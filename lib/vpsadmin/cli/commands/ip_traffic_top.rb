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

      opts.on('--unit [UNIT]', %w(bytes bits), 'Select data unit (bytes or bits)') do |v|
        @opts[:unit] = v.to_sym
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
      @api.ip_traffic_monitor.list(meta: {includes: 'ip_address'})
    end

    def render
      t = Time.now

      setpos(0, 0)
      addstr("#{File.basename($0)} ip_traffic top - #{t.strftime('%H:%M:%S')}, ")
      addstr("next update at #{(t + REFRESH_RATE).strftime('%H:%M:%S')}, ")
      addstr("unit: #{@opts[:unit]} per second")
      
      attron(color_pair(1))
      setpos(2, 0)
      header = sprintf(
          "%-30s %10s %10s %10s",
          'IP Address',
          'Rx',
          'Tx',
          'Total'
      )
      addstr(header + (' ' * (cols - header.size)) + "\n")
      attroff(color_pair(1))

      i = 3
      fetch.each do |data|
        setpos(i, 0)
        addstr(sprintf(
            "%-30s %10s %10s %10s",
            data.ip_address.addr,
            unitize(data.bytes_in, data.delta),
            unitize(data.bytes_out, data.delta),
            unitize(data.bytes, data.delta),
        ))

        i += 1
      end

      refresh
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
