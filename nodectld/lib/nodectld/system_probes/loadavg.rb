module NodeCtld::SystemProbes
  class LoadAvg
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

    attr_reader :avg

    def initialize(data = nil)
      data ||= File.read('/proc/loadavg')
      parsed = data.split(' ')

      @avg = {
        1 => parsed[0].to_f,
        5 => parsed[1].to_f,
        15 => parsed[2].to_f,
      }
    end
  end
end
