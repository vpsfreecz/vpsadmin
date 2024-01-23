class AddImpactType < ActiveRecord::Migration[7.1]
  class Outage < ActiveRecord::Base ; end

  def change
    add_column :outages, :impact_type, :integer, null: false, default: 0
    add_index :outages, :impact_type

    reversible do |dir|
      dir.up do
        Outage.all.each do |outage|
          outage.update!(
            impact_type: outage.outage_type,
            outage_type: outage.planned ? 0 : 1,
          )
        end
      end

      dir.down do
        Outage.all.each do |outage|
          outage.update!(
            outage_type: outage.impact_type,
            planned: outage.outage_type == 0,
          )
        end
      end
    end

    remove_index :outages, :planned
    remove_column :outages, :planned, :boolean, null: false, default: false

    remove_index :outage_updates, :outage_type
    rename_column :outage_updates, :outage_type, :impact_type
    add_index :outage_updates, :impact_type
  end
end
