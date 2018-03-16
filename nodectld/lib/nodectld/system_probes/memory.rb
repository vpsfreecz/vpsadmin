module NodeCtld::SystemProbes
  class Memory
    attr_reader :avg

    def initialize(data = nil)
      @data = {}

      (data || File.read('/proc/meminfo')).split("\n").each do |line|
        name, value, _ = line.split

        @data[ name.chop.downcase.to_sym ] = value.to_i
      end
    end

    def [](name)
      @data[name]
    end

    def total
      @data[:memtotal]
    end

    def free
      @data[:memfree]
    end

    def used
      total - free
    end

    def swap_total
      @data[:swaptotal]
    end

    def swap_free
      @data[:swapfree]
    end

    def swap_used
      swap_total - swap_free
    end
  end
end
