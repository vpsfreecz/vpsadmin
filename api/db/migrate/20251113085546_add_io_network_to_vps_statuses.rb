class AddIoNetworkToVpsStatuses < ActiveRecord::Migration[7.2]
  def change
    tables = %i[
      vps_current_statuses
      vps_statuses
    ]

    columns = %i[
      io_read_requests
      io_read_bytes

      io_write_requests
      io_write_bytes

      network_packets
      network_packets_in
      network_packets_out

      network_bytes
      network_bytes_in
      network_bytes_out
    ]

    tables.each do |table|
      columns.each do |column|
        add_column table, column, :bigint, null: true
      end
    end

    columns.each do |column|
      add_column :vps_current_statuses, :"sum_#{column}", :bigint, null: true
    end

    add_column :vps_current_statuses, :delta, :bigint, null: true
  end
end
