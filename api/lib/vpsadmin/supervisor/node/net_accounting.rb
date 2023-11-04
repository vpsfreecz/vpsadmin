require_relative 'base'

module VpsAdmin::Supervisor
  class Node::NetAccounting < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(queue_name('net_accounting'))

      queue.bind(exchange, routing_key: 'net_accounting')

      queue.subscribe do |_delivery_info, _properties, payload|
        accounting = JSON.parse(payload)['accounting']
        save_accounting(accounting)
      end
    end

    protected
    def save_accounting(accounting)
      kinds = [
        [:year, ::NetworkInterfaceYearlyAccounting],
        [:month, ::NetworkInterfaceMonthlyAccounting],
        [:day, ::NetworkInterfaceDailyAccounting],
      ]

      date_spec = []

      kinds.each do |kind, model|
        date_spec << kind

        model.upsert_all(
          accounting.map do |acc|
            t = Time.at(acc['time'])

            data = {
              network_interface_id: acc['id'],
              user_id: acc['user_id'],
              bytes_in: acc['bytes_in'],
              bytes_out: acc['bytes_out'],
              packets_in: acc['packets_in'],
              packets_out: acc['packets_out'],
              created_at: t,
              updated_at: t,
            }

            date_spec.each do |date_part|
              data[date_part] = t.send(date_part)
            end

            data
          end,
          update_only: %i(bytes_in bytes_out packets_in packets_out updated_at),
        )
      end
    end
  end
end
