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

    # syslog namespace tag
    # @return [String, nil]
    attr_reader :syslogns_tag

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
      params = line[0..(semicolon - 1)]
      msg = line[(semicolon + 1)..].strip

      if /^\[ \s*([a-zA-Z0-9_:-]+)\s* \] ([^$]+)/ =~ msg
        @syslogns_tag = ::Regexp.last_match(1)
        @text = ::Regexp.last_match(2)
      else
        @syslogns_tag = nil
        @text = msg
      end

      syslog, seq, timestamp, = params.split(',')

      @seq = seq.to_i
      @timestamp = timestamp.to_i
    end
  end
end
