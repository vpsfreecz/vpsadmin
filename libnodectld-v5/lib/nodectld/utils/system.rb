require 'libosctl'
require 'timeout'

module NodeCtld
  module Utils::System
    include Timeout
    include OsCtl::Lib::Utils::System

    def try_harder(attempts = 3, &)
      status, v = repeat_on_failure(attempts:, &)

      if status
        v
      else
        @output ||= {}
        @output[:attempts] = v.map do |err|
          {
            cmd: err.cmd,
            exitstatus: err.rc,
            error: err.output
          }
        end

        raise 'run out of attempts'
      end
    end
  end
end
