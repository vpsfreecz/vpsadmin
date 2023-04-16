class AddVpsSshHostKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :vps_ssh_host_keys do |t|
      t.references  :vps,                       null: false
      t.integer     :bits,                      null: false, unsigned: true
      t.string      :algorithm,                 null: false, limit: 30
      t.string      :fingerprint,               null: false, limit: 100
      t.timestamps                              null: false
    end

    add_index :vps_ssh_host_keys, %i(vps_id algorithm), unique: true
  end
end
