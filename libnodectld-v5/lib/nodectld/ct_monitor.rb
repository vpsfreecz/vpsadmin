require 'json'
require 'nodectld/daemon'

module NodeCtld
  # Interface to `osctl monitor`
  class CtMonitor
    include OsCtl::Lib::Utils::Log

    def initialize
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

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

        if vps_id > 0
          send_event(vps_id, 'state', { 'state' => event[:opts][:state] })
        end

        if vps_id > 0 && event[:opts][:state] == 'running'
          VpsPostStart.run(vps_id)
        end

        if vps_id > 0 && event[:opts][:state] == 'stopped'
          VethMap.reset(vps_id)
        end

        Daemon.instance.ct_top.refresh if %w[running stopped].include?(event[:opts][:state])

      when 'ct_exit'
        vps_id = event[:opts][:id].to_i

        if vps_id > 0
          send_event(vps_id, 'exit', { 'exit_type' => event[:opts][:exit_type] })
        end

      when 'osctl_oomd'
        vps_id = event[:opts][:id].to_i

        if vps_id > 0
          log(:info, "osctl-oomd action #{event[:opts][:action]} on VPS #{vps_id}")
          send_event(
            vps_id,
            'oomd',
            { 'action' => event[:opts][:action] },
            time: Time.at(event[:opts][:time])
          )
        end

      when 'osctld_shutdown'
        if Daemon.instance.node.any_osctl_pools?
          log(:info, 'osctld is shutting down, pausing')
          Daemon.instance.pause
          Daemon.instance.node.set_all_pools_down
        end
      end
    end

    def send_event(vps_id, type, opts, time: nil)
      NodeBunny.publish_wait(
        @exchange,
        {
          id: vps_id,
          time: (time || Time.now).to_i,
          type:,
          opts:
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_events'
      )
    end
  end
end
