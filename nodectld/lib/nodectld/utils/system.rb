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

    alias_method :libosctl_syscmd, :syscmd

    # Provide return value, so that commands don't have to explicitly
    # return `ok`.
    def syscmd(*args)
      ret = libosctl_syscmd(*args)
      ret[:ret] = :ok
      ret
    end
  end
end
