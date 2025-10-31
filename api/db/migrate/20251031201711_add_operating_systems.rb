class AddOperatingSystems < ActiveRecord::Migration[7.2]
  class OperatingSystem < ActiveRecord::Base; end

  class OsFamily < ActiveRecord::Base; end

  class Vps < ActiveRecord::Base; end

  def change
    create_table :operating_systems do |t|
      t.string        :name,             null: false, limit: 30
      t.string        :label,            null: false, limit: 50
      t.timestamps                       null: false
    end

    add_column :os_families, :operating_system_id, :bigint, null: true
    add_index :os_families, :operating_system_id

    add_column :vpses, :operating_system_id, :bigint, null: true
    add_index :vpses, :operating_system_id

    reversible do |dir|
      dir.up do
        linux = OperatingSystem.create!(name: 'linux', label: 'Linux')

        OsFamily.all.update_all(operating_system_id: linux.id)
        Vps.all.update_all(operating_system_id: linux.id)
      end
    end

    change_column_null :os_families, :operating_system_id, false
    change_column_null :vpses, :operating_system_id, false
  end
end
