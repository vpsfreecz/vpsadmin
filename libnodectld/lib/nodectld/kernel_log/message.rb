module NodeCtld
  class KernelLog::Message
    # Sequence number
    # @return [Integer]
    attr_reader :seq

    # Timestamp in microseconds from system boot
    # @return [Integer]
    attr_reader :timestamp

    # Time at which the message was read
    # @return [Time]
    attr_reader :time

    # The actual text message
    # @return [String]
    attr_reader :text

    # @param line [String]
    # @param time [Time]
    def initialize(line, time)
      @time = time
      @continuation = false
      parse(line)
    end

    def continuation?
      @continuation
    end

    protected
    def parse(line)
      if line.start_with?(' ')
        @continuation = true
        @text = line.strip
        return
      end

      semicolon = line.index(';')
      params = line[0..(semicolon-1)]
      @text = line[(semicolon+1)..-1].strip

      syslog, seq, timestamp, _ = params.split(',')

      @seq = seq.to_i
      @timestamp = timestamp.to_i
    end
  end
end
