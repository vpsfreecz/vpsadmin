require 'libosctl'
require 'net/http'

module NodeCtld
  # Fetch data from osctl-exporter
  class OsCtlExporter
    include OsCtl::Lib::Utils::Log

    def initialize
      @queue = OsCtl::Lib::Queue.new
    end

    def enable?
      cfg(:enable)
    end

    def start
      @thread = Thread.new { run }
    end

    def stop
      if @thread
        @queue << :stop
        @thread.join
        @thread = nil
      end
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

      db = Db.new
      t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

      vpses.each do |vps_id, procs|
        procs.each do |state, count|
          db.prepared(
            'INSERT INTO vps_os_processes
            SET vps_id = ?, `state` = ?, `count` = ?, created_at = ?, updated_at = ?
            ON DUPLICATE KEY UPDATE `count` = ?, updated_at = ?',
            vps_id, state, count, t, t, count, t
          )
        end
      end

      db.close
    end

    def cfg(key)
      $CFG.get(:osctl_exporter, key)
    end
  end
end
