require 'json'
require 'nodectld/daemon'

module NodeCtld
  # Interface to `osctl monitor`
  class CtMonitor
    include OsCtl::Lib::Utils::Log

    def start
      loop do
        run

        if stop?
          break

        else
          sleep(1)
        end
      end
    end

    def stop
      @stop = true
      pipe.close
    end

    def log_type
      'ct monitor'
    end

    protected
    attr_reader :pipe, :pid

    def run
      r, w = IO.pipe
      @pipe = r
      @pid = Process.spawn(
        'osctl', '-j', 'monitor',
        out: w, close_others: true
      )
      w.close

      log(:info, "Started with pid #{pid}")

      until pipe.eof?
        process_event(JSON.parse(pipe.readline, symbolize_names: true))
      end

      Process.wait(pid)
      log(:info, "Exited with pid #{$?.exitstatus}")
    end

    def stop?
      @stop
    end

    def process_event(event)
      case event[:type]
      when 'state'
        if event[:opts][:state] == 'stopped'
          MountReporter.report(event[:opts][:id], :all, :unmounted)
          VethMap.reset(event[:opts][:id].to_i)
        end

        if %w(running stopped).include?(event[:opts][:state])
          Daemon.instance.ct_top.refresh
        end

      when 'osctld_shutdown'
        log(:info, 'osctld is shutting down, pausing')
        Daemon.instance.pause
        Daemon.instance.node.set_all_pools_down
      end
    end
  end
end
