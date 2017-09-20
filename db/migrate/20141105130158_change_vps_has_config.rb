class ChangeVpsHasConfig < ActiveRecord::Migration
  class VpsHasConfig < ActiveRecord::Base

  end

  def up
    create_table :tmp do |t|
      t.integer     :vps_id,                  null: false
      t.integer     :config_id,               null: false
      t.integer     :order,                   null: false
      t.integer     :confirmed,               null: false
    end

    add_index :tmp, [:vps_id, :config_id, :confirmed], unique: true

    VpsHasConfig.connection.execute('INSERT INTO tmp (vps_id, config_id, `order`, confirmed)
                                     SELECT vps_id, config_id, `order`, 1 FROM vps_has_config')

    drop_table :vps_has_config
    rename_table :tmp, :vps_has_config
  end

  def down
    create_table :tmp, id: false do |t|
      t.integer     :vps_id,                  null: false
      t.integer     :config_id,               null: false
      t.integer     :order,                   null: false
      t.integer     :confirmed,               null: false
    end

    VpsHasConfig.connection.execute('ALTER TABLE tmp ADD PRIMARY KEY(vps_id, config_id)')
    VpsHasConfig.connection.execute('INSERT INTO tmp (vps_id, config_id, `order`, confirmed)
                                     SELECT vps_id, config_id, `order`, confirmed FROM vps_has_config')

    drop_table :vps_has_config
    rename_table :tmp, :vps_has_config
  end
end
