module VpsAdmind::Utils
  module OutageWindow
    class OutageWindows < Array
      def open?
        wday = Time.now.wday
        today = detect { |w| w.weekday == wday }
        return false unless today
        return today.open?
      end

      def closest
        t = Time.now
        now_in_mins = t.hour * 60 + t.min

        return first if first.opens_today?
        return size > 1 ? self[1] : first
      end
    end

    class OutageWindow
      attr_reader :weekday, :opens_at, :closes_at, :reserve_time
      
      def initialize(cmd, w, reserve_time)
        @cmd = cmd

        w.each do |k, v|
          instance_variable_set("@#{k}", v)
        end

        @reserve_time = reserve_time
      end

      def open?
        t = Time.now
        now_in_mins = t.hour * 60 + t.min

        t.wday == weekday \
           && now_in_mins >= opens_at \
           && now_in_mins <= (closes_at - reserve_time)
      end

      def opens_today?
        t = Time.now
        now_in_mins = t.hour * 60 + t.min

        t.wday == weekday && opens_at >= now_in_mins
      end

      def open_time
        now = Time.now
        t = nil

        if now.wday == weekday
          if opens_today?
            t = Time.local(now.year, now.month, now.day, opens_at / 60, opens_at % 60)

          else # will open on this week day, but next week
            today = Time.local(now.year, now.month, now.day)
            t = today + 7*24*60*60 + (opens_at * 60)
          end

        else # will open the next or some later day
          # Start with tomorrow
          t = Time.local(now.year, now.month, now.day) + 24*60*60
          return (t + opens_at*60) if t.wday == weekday

          # Iterate over all 6 remaining days, find our day of week
          6.times do
            t = t + 24*60*60
            break if t.wday == weekday
          end

          t = t + opens_at*60
        end

        t
      end

      def wait
        t = Time.now
        opens_t = open_time
        delta = opens_t - t

        @cmd.step = "waiting till #{t + delta}"
        sleep(delta + 10)

        fail 'not in the window' unless open?
      end
    end

    def windows
      return @obj_windows if @obj_windows

      @obj_windows = OutageWindows.new
      weekday = Time.now.wday
      
      # Rearrange windows so that today's window is first, tomorrow's second
      # and so on.
      if weekday == 0
        windows = @windows

      else
        windows = @windows.select { |w| w['weekday'] >= weekday }
        windows.concat(@windows.select { |w| w['weekday'] < weekday })
      end

      fail 'no outage window available' if windows.empty?

      windows.each do |w|
        @obj_windows << OutageWindow.new(self, w, @reserve_time)
      end

      @obj_windows
    end
  end
end
