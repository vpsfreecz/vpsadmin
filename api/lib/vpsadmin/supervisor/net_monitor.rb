module VpsAdmin::Supervisor
  class NetMonitor
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(10)

      exchange = @channel.direct('node.net_monitor')
      queue = @channel.queue('node.net_monitor')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        monitors = JSON.parse(payload)['monitors']
        monitors.each do |mon|
          update_monitor(mon)
        end
      end
    end

    protected
    def update_monitor(mon)
      t = Time.at(mon['time'])

      ActiveRecord::Base.connection.exec_query(
        ::NetworkInterfaceMonitor.sanitize_sql_for_assignment([
          'INSERT INTO network_interface_monitors SET
            network_interface_id = ?,
            bytes = ?,
            bytes_in = ?,
            bytes_out = ?,
            packets = ?,
            packets_in = ?,
            packets_out = ?,
            delta = ?,
            bytes_in_readout = ?,
            bytes_out_readout = ?,
            packets_in_readout = ?,
            packets_out_readout = ?,
            created_at = ?,
            updated_at = ?
          ON DUPLICATE KEY UPDATE
            bytes = values(bytes),
            bytes_in = values(bytes_in),
            bytes_out = values(bytes_out),
            packets = values(packets),
            packets_in = values(packets_in),
            packets_out = values(packets_out),
            delta = values(delta),
            bytes_in_readout = values(bytes_in_readout),
            bytes_out_readout = values(bytes_out_readout),
            packets_in_readout = values(packets_in_readout),
            packets_out_readout = values(packets_out_readout),
            updated_at = values(updated_at)',
          mon['id'],
          mon['bytes_in'] + mon['bytes_out'],
          mon['bytes_in'],
          mon['bytes_out'],
          mon['packets_in'] + mon['packets_out'],
          mon['packets_in'],
          mon['packets_out'],
          mon['delta'],
          mon['bytes_in_readout'],
          mon['bytes_out_readout'],
          mon['packets_in_readout'],
          mon['packets_out_readout'],
          t,
          t,
        ])
      )
    end
  end
end
