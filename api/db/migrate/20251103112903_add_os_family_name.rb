class AddOsFamilyName < ActiveRecord::Migration[7.2]
  class OsFamily < ActiveRecord::Base; end

  class OsTemplate < ActiveRecord::Base; end

  def change
    add_column :os_families, :name, :string, null: true, limit: 50

    reversible do |dir|
      dir.up do
        OsFamily.all.each do |family|
          tpl = OsTemplate.where(os_family_id: family.id).where.not(distribution: nil).take
          family.update!(name: tpl ? tpl.distribution : family.label.downcase.gsub(' ', ''))
        end
      end
    end

    change_column_null :os_families, :name, false
  end
end
