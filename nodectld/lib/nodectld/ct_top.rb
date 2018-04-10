require 'json'
require 'libosctl'
require 'thread'

module NodeCtld
  # Interface to `osctl ct top`
  class CtTop
    include OsCtl::Lib::Utils::Log

    def initialize
      @mutex = Mutex.new
      @refresher = Thread.new do
        loop do
          sleep(10)

          sync do
            next if !pid || !@refresh || @refresh > Time.now

            log(:info, 'Refreshing VPS statuses')
            Process.kill('USR1', pid)
            @refresh = false
          end
        end
      end
    end

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
      # Refresh VPS statuses in 3 seconds. This should give `osctl ct top`
      # controller by {CtTop} to register newly started VPSes.
      sync { @refresh = Time.now + 3 }
    end

    def stop
      sync { @stop = true }
      pipe.close
      @refresher.terminate
    end

    def log_type
      'ct top'
    end

    protected
    attr_reader :rate, :pipe, :pid

    def run
      r, w = IO.pipe
      @pipe = r
      pid = Process.spawn(
        'osctl', '-j', 'ct', 'top', '--rate', rate.to_s,
        out: w, close_others: true
      )
      w.close

      log(:info, "Started with pid #{pid}")

      sync { @pid = pid }

      until pipe.eof?
        data = JSON.parse(pipe.readline, symbolize_names: true)
        sync { @refresh = false }
        yield(data)
      end

      Process.wait(pid)
      log(:info, "Exited with pid #{$?.exitstatus}")
    end

    def stop?
      sync { @stop }
    end

    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
