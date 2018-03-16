module NodeCtld::SystemProbes
  class LoadAvg
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

    attr_reader :avg

    def initialize(data = nil)
      if /solaris/ =~ RUBY_PLATFORM
        solaris(data)

      else
        linux(data)
      end
    end

    protected
    def linux(data)
      data ||= File.read('/proc/loadavg')
      parsed = data.split(' ')

      @avg = {
          1 => parsed[0].to_f,
          5 => parsed[1].to_f,
          15 => parsed[2].to_f,
      }
    end

    def solaris(data)
      m = /load average\: (\d+\.\d+), (\d+\.\d+), (\d+\.\d+)/.match(
          syscmd($CFG.get(:bin, :uptime))[:output]
      )

      @avg = {1 => m[1], 5 => m[2], 15 => m[3]}
    end
  end
end
