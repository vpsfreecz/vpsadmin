require 'json'
require 'nodectld/daemon'

module NodeCtld
  # Interface to `osctl monitor`
  class CtMonitor
    include OsCtl::Lib::Utils::Log

    def start
      loop do
        run

        break if stop?

        sleep(1)
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

      process_event(JSON.parse(pipe.readline, symbolize_names: true)) until pipe.eof?

      Process.wait(pid)
      log(:info, "Exited with pid #{$?.exitstatus}")
    end

    def stop?
      @stop
    end

    def process_event(event)
      case event[:type]
      when 'state'
        vps_id = event[:opts][:id].to_i

        VpsSshHostKeys.schedule_update_vps(vps_id) if vps_id > 0 && event[:opts][:state] == 'running'

        if vps_id > 0 && event[:opts][:state] == 'stopped'
          MountReporter.report(event[:opts][:id], :all, :unmounted)
          VethMap.reset(vps_id)
        end

        Daemon.instance.ct_top.refresh if %w[running stopped].include?(event[:opts][:state])

      when 'osctld_shutdown'
        if Daemon.instance.node.any_osctl_pools?
          log(:info, 'osctld is shutting down, pausing')
          Daemon.instance.pause
          Daemon.instance.node.set_all_pools_down
        end
      end
    end
  end
end
