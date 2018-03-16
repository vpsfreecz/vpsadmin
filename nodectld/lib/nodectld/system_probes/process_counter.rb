module NodeCtld::SystemProbes
  class ProcessCounter
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

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
