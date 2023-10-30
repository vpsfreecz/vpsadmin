module VpsAdmin::Supervisor
  class NetAccounting
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(10)

      exchange = @channel.direct('node.net_accounting')
      queue = @channel.queue('node.net_accounting')

      queue.bind(exchange)

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
