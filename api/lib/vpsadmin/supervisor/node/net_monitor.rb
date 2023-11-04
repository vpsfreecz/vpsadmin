require_relative 'base'

module VpsAdmin::Supervisor
  class Node::NetMonitor < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(queue_name('net_monitor'))

      queue.bind(exchange, routing_key: 'net_monitor')

      queue.subscribe do |_delivery_info, _properties, payload|
        monitors = JSON.parse(payload)['monitors']
        update_monitors(monitors)
      end
    end

    protected
    def update_monitors(monitors)
      ::NetworkInterfaceMonitor.upsert_all(
        monitors.map do |m|
          t = Time.at(m['time'])

          {
            network_interface_id: m['id'],
            bytes: m['bytes_in'] + m['bytes_out'],
            bytes_in: m['bytes_in'],
            bytes_out: m['bytes_out'],
            packets: m['packets_in'] + m['packets_out'],
            packets_in: m['packets_in'],
            packets_out: m['packets_out'],
            delta: m['delta'],
            bytes_in_readout: m['bytes_in_readout'],
            bytes_out_readout: m['bytes_out_readout'],
            packets_in_readout: m['packets_in_readout'],
            packets_out_readout: m['packets_out_readout'],
            created_at: t,
            updated_at: t,
          }
        end,
        update_only: %i(
          bytes bytes_in bytes_out
          packets packets_in packets_out
          delta
          bytes_in_readout bytes_out_readout
          packets_in_readout packets_out_readout
          updated_at
        ),
      )
    end
  end
end
