require_relative 'base'

module VpsAdmin::Supervisor
  class Node::NetAccounting < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('net_accounting'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'net_accounting')

      queue.subscribe do |_delivery_info, _properties, payload|
        accounting = JSON.parse(payload)['accounting']
        save_accounting(accounting)
      end
    end

    protected

    def save_accounting(accounting)
      netifs =
        ::NetworkInterface
        .joins(:vps)
        .includes(:vps)
        .where(
          id: accounting.map { |acc| acc['id'] },
          vpses: { node_id: node.id }
        )
        .index_by(&:id)

      kinds = [
        [:year, ::NetworkInterfaceYearlyAccounting],
        [:month, ::NetworkInterfaceMonthlyAccounting],
        [:day, ::NetworkInterfaceDailyAccounting]
      ]

      date_spec = []

      kinds.each do |kind, model|
        date_spec << kind

        rows = accounting.filter_map do |acc|
          netif = netifs[acc['id']]
          next if netif.nil?

          t = Time.at(acc['time'])

          data = {
            network_interface_id: netif.id,
            user_id: netif.vps.user_id,
            bytes_in: acc['bytes_in'],
            bytes_out: acc['bytes_out'],
            packets_in: acc['packets_in'],
            packets_out: acc['packets_out'],
            created_at: t,
            updated_at: t
          }

          date_spec.each do |date_part|
            data[date_part] = t.send(date_part)
          end

          data
        end

        next if rows.empty?

        model.upsert_all(
          rows,
          on_duplicate: Arel.sql('
            bytes_in = bytes_in + values(bytes_in),
            bytes_out = bytes_out + values(bytes_out),
            packets_in = packets_in + values(packets_in),
            packets_out = packets_out + values(packets_out),
            updated_at = values(updated_at)
          ')
        )
      end
    end
  end
end
