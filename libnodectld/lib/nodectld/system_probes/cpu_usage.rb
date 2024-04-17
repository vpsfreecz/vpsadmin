module NodeCtld::SystemProbes
  class CpuUsage
    FIELDS = %i[
      user
      nice
      system
      idle
      iowait
      irq
      softirq
      steal
      guest
      guest_nice
    ].freeze

    # @return [Hash]
    attr_reader :values

    def initialize
      @data = []
      @values = FIELDS.to_h { |v| [v, 0.0] }
      @values[:idle] = 100.0
    end

    def start
      @thread = Thread.new do
        loop do
          measure_once
          sleep($CFG.get(:node, :cpu_usage_measure_delay))
          measure_once
          @values = to_percent
          @data.clear
        end
      end

      nil
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

        data[FIELDS[i]] = v.to_i
      end

      @data << data
      nil
    end

    protected

    def to_percent
      data = diff
      sum = data.values.reduce(:+).to_f

      data.transform_values do |v|
        sum > 0 ? (v / sum * 100).round(2) : 0.0
      end
    end

    def diff
      ret = {}

      d1, d2 = @data

      d1.each_key do |k|
        ret[k] = d2[k] - d1[k]
        ret[k] = 0 if ret[k] < 0
      end

      ret
    end
  end
end
