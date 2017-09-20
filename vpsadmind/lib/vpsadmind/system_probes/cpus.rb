module VpsAdmind::SystemProbes
  class Cpus
    include VpsAdmind::Utils::Log
    include VpsAdmind::Utils::System

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
