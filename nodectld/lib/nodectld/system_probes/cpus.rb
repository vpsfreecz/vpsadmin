module NodeCtld::SystemProbes
  class Cpus
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System

    attr_reader :count

    def initialize
      ['getconf _NPROCESSORS_ONLN', 'nproc'].each do |cmd|
        v = syscmd(cmd)[:output]

        if $?.exitstatus == 0
          @count = v.strip.to_i
          return
        end
      end

      @count = -1
    end
  end
end
