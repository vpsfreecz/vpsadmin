module VpsAdmin::Supervisor
  class VpsOsProcesses
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(5)

      exchange = @channel.direct('node.vps_os_processes')
      queue = @channel.queue('node.vps_os_processes')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        vps_procs = JSON.parse(payload)
        update_vps_processes(vps_procs)
      end
    end

    protected
    def update_vps_processes(vps_procs)
      t = Time.at(vps_procs['time'])

      vps_procs['vps_processes'].each do |vps_proc|
        vps_proc['processes'].each do |state, count|
          ActiveRecord::Base.connection.exec_query(
            ::VpsOsProcess.sanitize_sql_for_assignment([
              'INSERT INTO vps_os_processes
              SET vps_id = ?, `state` = ?, `count` = ?, created_at = ?, updated_at = ?
              ON DUPLICATE KEY UPDATE `count` = ?, updated_at = ?',
              vps_proc['vps_id'], state, count, t, t,
              count, t,
            ])
          )
        end
      end
    end
  end
end
