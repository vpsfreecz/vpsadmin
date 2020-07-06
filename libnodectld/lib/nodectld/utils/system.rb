require 'libosctl'
require 'timeout'

module NodeCtld
  module Utils::System
    include Timeout
    include OsCtl::Lib::Utils::System

    def try_harder(attempts = 3, &block)
      status, v = repeat_on_failure(attempts: attempts, &block)

      if status
        v
      else
        @output ||= {}
        @output[:attempts] = v.map do |err|
          {
            cmd: err.cmd,
            exitstatus: err.rc,
            error: err.output,
          }
        end

        fail 'run out of attempts'
      end
    end
  end
end
