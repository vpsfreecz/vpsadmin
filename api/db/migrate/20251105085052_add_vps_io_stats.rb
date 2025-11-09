class AddVpsIoStats < ActiveRecord::Migration[7.2]
  class StorageVolume < ActiveRecord::Base; end

  class VpsIoStat < ActiveRecord::Base; end

  def change
    create_table :vps_io_stats do |t|
      t.references  :vps,                    null: false
      t.references  :storage_volume,         null: false
      t.bigint      :read_requests,          null: false, default: 0
      t.bigint      :read_bytes,             null: false, default: 0
      t.bigint      :write_requests,         null: false, default: 0
      t.bigint      :write_bytes,            null: false, default: 0
      t.integer     :delta,                  null: false, default: 1
      t.bigint      :read_requests_readout,  null: false, default: 0
      t.bigint      :read_bytes_readout,     null: false, default: 0
      t.bigint      :write_requests_readout, null: false, default: 0
      t.bigint      :write_bytes_readout,    null: false, default: 0
      t.timestamps                           null: false
    end

    add_index :vps_io_stats, %i[vps_id storage_volume_id], unique: true

    reversible do |dir|
      dir.up do
        StorageVolume.all.each do |vol|
          VpsIoStat.create!(
            vps_id: vol.vps_id,
            storage_volume_id: vol.id,
            delta: 1
          )
        end
      end
    end
  end
end
