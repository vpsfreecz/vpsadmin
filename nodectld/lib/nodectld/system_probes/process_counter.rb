module NodeCtld::SystemProbes
  class ProcessCounter
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

    attr_reader :count

    def initialize
      @count = syscmd('ps axh -opid | wc -l')[:output].strip.to_i
    end
  end
end
