module NodeCtld::SystemProbes
  class Uptime
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

    attr_reader :uptime, :idle_process

    def initialize(data = nil)
      data ||= File.read('/proc/uptime')
      parsed = data.split(' ')

      @uptime = parsed[0].to_f
      @idle_process = parsed[1].to_f
    end
  end
end
