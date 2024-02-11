class AddVpsOsProcesses < ActiveRecord::Migration[6.1]
  def change
    create_table :vps_os_processes do |t|
      t.references  :vps,                   null: false
      t.string      :state,                 null: false, limit: 5, index: true
      t.integer     :count,                 null: false, unsigned: true
      t.timestamps                          null: false
    end

    add_index :vps_os_processes, %i[vps_id state], unique: true
  end
end
