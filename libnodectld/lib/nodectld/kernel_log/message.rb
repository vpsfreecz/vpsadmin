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

    # VPS ID extracted from syslog namespace tag
    #
    # Note that the tag has limited length, so the ID might be truncated
    # if it is too long.
    # @return [Integer, nil]
    attr_reader :vps_id

    # The actual text message
    # @return [String]
    attr_reader :text

    # @param line [String]
    # @param time [Time]
    def initialize(line, time)
      @time = time
      @continuation = false
      @vps_id = nil
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

        @vps_id =
          if @syslogns_tag.include?(':')
            _, vps_id = @syslogns_tag.split(':')
            vps_id.to_i
          else
            @syslogns_tag.to_i
          end
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
