require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsOsProcesses < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('vps_os_processes'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_os_processes')

      queue.subscribe do |_delivery_info, _properties, payload|
        vps_procs = JSON.parse(payload)
        update_vps_processes(vps_procs)
      end
    end

    protected

    def update_vps_processes(vps_procs)
      t = Time.at(vps_procs['time'])
      vps_ids = vps_procs['vps_processes'].map { |vps_proc| vps_proc['vps_id'] }
      known_vps_ids = ::Vps.where(id: vps_ids, node_id: node.id).pluck(:id)

      vps_procs['vps_processes'].each do |vps_proc|
        vps_id = vps_proc['vps_id']
        next unless known_vps_ids.include?(vps_id)

        states = vps_proc['processes'].keys

        stale = ::VpsOsProcess.where(vps_id:)
        stale = stale.where.not(state: states) if states.any?
        stale.delete_all

        next if states.empty?

        ::VpsOsProcess.upsert_all(
          vps_proc['processes'].map do |state, count|
            {
              vps_id:,
              state:,
              count:,
              created_at: t,
              updated_at: t
            }
          end,
          update_only: %i[count updated_at]
        )
      end
    end
  end
end
