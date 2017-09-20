module VpsAdmind::SystemProbes
  class Uptime
    include VpsAdmind::Utils::Log
    include VpsAdmind::Utils::System

    attr_reader :uptime, :idle_process

    def initialize(data = nil)
      if /solaris/ =~ RUBY_PLATFORM
        solaris(data)

      else
        linux(data)
      end
    end

    protected
    def linux(data)
      data ||= File.read('/proc/uptime')
      parsed = data.split(' ')

      @uptime = parsed[0].to_f
      @idle_process = parsed[1].to_f
    end

    def solaris(data)
      _, boot = syscmd('kstat -p unix:0:system_misc:boot_time')[:output].strip.split

      @uptime = Time.now.to_i - boot.to_i
    end
  end
end
