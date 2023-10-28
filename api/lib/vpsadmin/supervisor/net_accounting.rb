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
        accounting.each do |acc|
          save_accounting(acc)
        end
      end
    end

    protected
    def save_accounting(acc)
      kinds = [
        [:year, ::NetworkInterfaceYearlyAccounting],
        [:month, ::NetworkInterfaceMonthlyAccounting],
        [:day, ::NetworkInterfaceDailyAccounting],
      ]
      date_spec = {}
      t = Time.at(acc['time'])

      kinds.each do |kind, model|
        date_spec[kind.to_s] = t.send(kind)

        ActiveRecord::Base.connection.exec_query(
          model.sanitize_sql_for_assignment([
            "INSERT INTO #{model.table_name} SET
              network_interface_id = ?,
              user_id = ?,
              #{date_spec.map { |k, v| "`#{k}` = #{v}" }.join(', ')},
              bytes_in = ?,
              bytes_out = ?,
              packets_in = ?,
              packets_out = ?,
              created_at = ?,
              updated_at = ?
            ON DUPLICATE KEY UPDATE
              user_id = values(user_id),
              bytes_in = bytes_in + values(bytes_in),
              bytes_out = bytes_out + values(bytes_out),
              packets_in = packets_in + values(packets_in),
              packets_out = packets_out + values(packets_out),
              updated_at = values(updated_at)
            ",
            acc['id'],
            acc['user_id'],
            acc['bytes_in'],
            acc['bytes_out'],
            acc['packets_in'],
            acc['packets_out'],
            t,
            t,
          ])
        )
      end
    end
  end
end
