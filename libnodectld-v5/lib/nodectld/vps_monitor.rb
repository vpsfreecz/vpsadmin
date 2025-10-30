require 'json'
require 'nodectld/daemon'

module NodeCtld
  class VpsMonitor
    include OsCtl::Lib::Utils::Log

    Event = Struct.new(:type, :domain, :event, :detail, keyword_init: true)

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
      'vps monitor'
    end

    protected

    attr_reader :pipe, :pid

    def run
      r, w = IO.pipe
      @pipe = r
      @pid = Process.spawn(
        'virsh', 'event', '--event', 'lifecycle', '--loop',
        out: w, close_others: true
      )
      w.close

      log(:info, "Started with pid #{pid}")

      until pipe.eof?
        event = parse_event(pipe.readline)
        next if event.nil?

        process_event(event)
      end

      Process.wait(pid)
      log(:info, "Exited with pid #{$?.exitstatus}")
    end

    def stop?
      @stop
    end

    def parse_event(line)
      return if /\Aevent 'lifecycle' for domain '([^']+)': ([^\s]+) ([^\z]+)\z/ !~ line

      Event.new(
        type: 'lifecycle',
        domain: ::Regexp.last_match(1),
        event: ::Regexp.last_match(2).downcase,
        detail: ::Regexp.last_match(3).downcase
      )
    end

    def process_event(event)
      return if event.type != 'lifecycle'

      vps_id = event.domain.to_i
      return if vps_id <= 0

      log(:info, "Lifecycle vps_id=#{vps_id}, event=#{event.event}, detail=#{event.detail}")

      send_event(vps_id, 'lifecycle', {
        event: event.event,
        detail: event.detail
      })

      case event.event
      when 'started'
        VpsPostStart.run(vps_id)
      when 'stopped'
        VpsPostStart.cancel(vps_id)
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
