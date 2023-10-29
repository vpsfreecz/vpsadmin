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
        ::VpsOsProcess.upsert_all(
          vps_proc['processes'].map do |state, count|
            {
              vps_id: vps_proc['vps_id'],
              state: state,
              count: count,
              created_at: t,
              updated_at: t,
            }
          end,
          update_only: %i(count),
        )
      end
    end
  end
end
