module VpsAdmind::SystemProbes
  class ProcessCounter
    include VpsAdmind::Utils::Log
    include VpsAdmind::Utils::System

    attr_reader :count

    def initialize
      if /solaris/ =~ RUBY_PLATFORM
        @count = syscmd('ps -A -o pid | wc -l')[:output].strip.to_i - 1

      else
        @count = syscmd('ps axh -opid | wc -l')[:output].strip.to_i
      end
    end
  end
end
