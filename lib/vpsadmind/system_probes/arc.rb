module VpsAdmind::SystemProbes
  class Arc
    def initialize
      @data = {}

      File.readlines('/proc/spl/kstat/zfs/arcstats')[2..-1].each do |line|
        name, type, value = line.split

        @data[ name.to_sym ] = value.to_i
      end
    end

    def hit_percent
      sum = @data[:hits] + @data[:misses]
      @data[:hits].to_f / sum * 100
    end

    def method_missing(name, *args)
      return @data[name] if @data.has_key?(name) && args.empty?
      super(name, *args)
    end
  end
end
