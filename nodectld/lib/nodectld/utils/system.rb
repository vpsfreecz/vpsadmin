require 'libosctl'
require 'timeout'

module NodeCtld
  module Utils::System
    include Timeout
    include OsCtl::Lib::Utils::System

    def try_harder(attempts = 3, &block)
      @output ||= {}
      @output[:attempts] = repeat_on_failure(attemps: attempts, &block).map do |exc|
        {
          cmd: err.cmd,
          exitstatus: err.rc,
          error: err.output,
        }
      end
    end

    libosctl_syscmd = instance_method(:syscmd)

    # Provide return value, so that commands don't have to explicitly
    # return `ok`.
    define_method(:syscmd) do |*args|
      ret = libosctl_syscmd.bind(self).(*args)
      ret[:ret] = :ok
      ret
    end
  end
end
