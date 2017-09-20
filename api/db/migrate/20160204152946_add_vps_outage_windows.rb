class AddVpsOutageWindows < ActiveRecord::Migration
  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'
  end

  class VpsOutageWindow < ActiveRecord::Base ; end

  def change
    create_table :vps_outage_windows do |t|
      t.references  :vps,               null: false
      t.integer     :weekday,           null: false
      t.boolean     :is_open,           null: false
      t.integer     :opens_at,          null: true
      t.integer     :closes_at,         null: true
    end

    add_index :vps_outage_windows, [:vps_id, :weekday], unique: true

    reversible do |dir|
      dir.up do
        Vps.where('object_state < 3').each do |vps|
          7.times do |i|
            VpsOutageWindow.create!(
                vps_id: vps.id,
                weekday: i,
                is_open: true,
                opens_at: 60,
                closes_at: 5*60,
            )
          end
        end
      end
    end
  end
end
