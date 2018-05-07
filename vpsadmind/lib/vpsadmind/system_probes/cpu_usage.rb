module VpsAdmind::SystemProbes
  class CpuUsage
    FIELDS = [
        :user,
        :nice,
        :system,
        :idle,
        :iowait,
        :irq,
        :softirq,
        :steal,
        :guest,
        :guest_nice,
    ]

    def initialize
      @data = []
    end

    def measure(delay = 0.3)
      measure_once
      sleep(delay)
      measure_once
      self
    end

    def measure_once(str = nil)
      unless str
        f = File.open('/proc/stat')
        str = f.readline
        f.close
      end

      # The input string may contain multiple lines. We're interested only in the
      # first line.
      values = str.split("\n").first.split
      data = {}

      FIELDS.each_index do |i|
        v = values[i + 1]
        break unless v

        data[ FIELDS[i] ] = v.to_i
      end

      @data << data
      self
    end

    def to_percent
      data = diff
      sum = data.values.reduce(:+).to_f
      ret = {}

      data.each do |k, v|
        if v == 0 || sum == 0.0
          ret[k] = 0

        else
          ret[k] = (v / sum * 100).round(2)
        end
      end

      ret
    end

    protected
    def diff
      ret = {}

      d1, d2 = @data

      d1.each_key do |k|
        ret[k] = d2[k] - d1[k]
      end

      ret
    end
  end
end
