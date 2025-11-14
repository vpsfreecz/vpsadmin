class AddVpsIoStatLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :vps_io_stat_logs do |t|
      t.references  :vps,             null: false
      t.references  :storage_volume,  null: false
      t.bigint      :read_requests,   null: false, default: 0
      t.bigint      :read_bytes,      null: false, default: 0
      t.bigint      :write_requests,  null: false, default: 0
      t.bigint      :write_bytes,     null: false, default: 0
      t.bigint      :fs_used,         null: true
      t.bigint      :fs_total,        null: true
      t.timestamps                    null: false
    end

    %w[read_requests read_bytes write_requests write_bytes].each do |col|
      add_column :vps_io_stats, :"sum_#{col}", :bigint, null: false, default: 0
    end
  end
end
