require 'json'
require 'libosctl'

module NodeCtld
  # Interface to `osctl ct top`
  class CtTop
    include OsCtl::Lib::Utils::Log

    # @param rate [Integer] refresh frequency in seconds
    # @yieldparam [Hash] data from ct top
    def monitor(rate, &block)
      @rate = rate

      loop do
        run(&block)

        if stop?
          break

        else
          sleep(1)
        end
      end
    end

    def refresh
      return unless pid
      log(:info, 'Refreshing VPS statuses')

      # TODO: allow one refresh every 5-10 seconds
      Process.kill('USR1', pid)
    end

    def stop
      @stop = true
      pipe.close
    end

    def log_type
      'ct top'
    end

    protected
    attr_reader :rate, :pipe, :pid

    def run
      r, w = IO.pipe
      @pipe = r
      @pid = Process.spawn(
        'osctl', '-j', 'ct', 'top', '--rate', rate.to_s,
        out: w, close_others: true
      )
      w.close

      log(:info, "Started with pid #{pid}")

      until pipe.eof?
        yield(JSON.parse(pipe.readline, symbolize_names: true))
      end

      Process.wait(pid)
      log(:info, "Exited with pid #{$?.exitstatus}")
    end

    def stop?
      @stop
    end
  end
end
