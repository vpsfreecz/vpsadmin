class AddOperatingSystems < ActiveRecord::Migration[7.2]
  class Os < ActiveRecord::Base
    has_many :os_families
  end

  class OsFamily < ActiveRecord::Base
    has_many :os_templates
  end

  class OsTemplate < ActiveRecord::Base
    belongs_to :os_family
    has_many :vpses
  end

  class Vps < ActiveRecord::Base
    belongs_to :os_template
  end

  def change
    create_table :oses do |t|
      t.string        :name,             null: false, limit: 30
      t.string        :label,            null: false, limit: 50
      t.timestamps                       null: false
    end

    add_column :os_families, :os_id, :bigint, null: true
    add_index :os_families, :os_id

    add_column :vpses, :os_family_id, :bigint, null: true
    add_index :vpses, :os_family_id

    reversible do |dir|
      dir.up do
        linux = Os.create!(name: 'linux', label: 'Linux')

        OsFamily.all.update_all(os_id: linux.id)

        Vps.all.each do |vps|
          vps.update!(os_family_id: vps.os_template.os_family_id)
        end
      end
    end

    change_column_null :os_families, :os_id, false
    change_column_null :vpses, :os_family_id, false
  end
end
