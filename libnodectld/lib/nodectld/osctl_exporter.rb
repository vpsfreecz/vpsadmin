require 'libosctl'
require 'net/http'

module NodeCtld
  # Fetch data from osctl-exporter
  class OsCtlExporter
    include OsCtl::Lib::Utils::Log

    def initialize
      @queue = OsCtl::Lib::Queue.new
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def enable?
      cfg(:enable)
    end

    def start
      @thread = Thread.new { run }
    end

    def stop
      return unless @thread

      @queue << :stop
      @thread.join
      @thread = nil
    end

    def log_type
      'osctl-exporter'
    end

    protected

    def run
      loop do
        v = @queue.pop(timeout: cfg(:interval))
        return if v == :stop

        data = fetch
        process(data) if data
      end
    end

    def fetch
      uri = URI(cfg(:url))
      ret = nil

      begin
        Net::HTTP.start(uri.host, uri.port) do |http|
          request = Net::HTTP::Get.new(uri)
          request['Accept'] = 'application/json'

          response = http.request(request)

          begin
            ret = JSON.parse(response.body)
          rescue JSON::ParserError => e
            log(:warn, "Unable to parse response from osctl-exporter: #{e.message}")
            return
          end
        end
      rescue SystemCallError => e
        log(:warn, "Unable to fetch response from osctl-exporter: #{e.message} (#{e.class})")
        return
      end

      ret
    end

    def process(data)
      save_os_processes(data['osctl_container_processes_state'])
    end

    def save_os_processes(processes_state)
      return if processes_state.nil?

      vpses = {}

      processes_state.each do |metric|
        vps_id = metric['labels']['id'].to_i
        next if vps_id <= 0

        vpses[vps_id] ||= {}
        vpses[vps_id][metric['labels']['state']] = metric['value']
      end

      return if vpses.empty?

      t = Time.now
      to_save = []
      max_size = cfg(:batch_size)

      vpses.each do |vps_id, procs|
        to_save << {
          vps_id: vps_id,
          processes: procs
        }

        save_processes(t, to_save, max_size)
      end

      save_processes(t, to_save)
    end

    def save_processes(time, to_save, max_size = 0)
      return if to_save.length <= max_size

      NodeBunny.publish_drop(
        @exchange,
        {
          time: time.to_i,
          vps_processes: to_save
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_os_processes'
      )

      to_save.clear
    end

    def cfg(key)
      $CFG.get(:osctl_exporter, key)
    end
  end
end
