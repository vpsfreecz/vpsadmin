require 'libosctl'

module NodeCtld
  class KernelLog::Event
    class Error < ::StandardError ; end

    # @param msg [KernelLog::Message]
    def self.start?(msg)
      raise NotImplementedError
    end

    include OsCtl::Lib::Utils::Log

    def initialize
      @finished = false
    end

    # @param msg [KernelLog::Message]
    def start(msg)
    end

    # @param msg [KernelLog::Message]
    def <<(msg)
    end

    # @param count [Integer]
    def lost_messages(count)
    end

    # @return [Boolean]
    def finished?
      @finished
    end

    def close
    end

    protected
    # @param rx [Regexp]
    # @param text [String]
    # @return [MatchData]
    def match_or_fail!(rx, text)
      m = rx.match(text)

      if m.nil?
        raise Error, "#{inspect(rx)} did not match #{inspect(msg.text)}"
      end

      m
    end

    def finish!
      @finished = true
    end
  end
end
