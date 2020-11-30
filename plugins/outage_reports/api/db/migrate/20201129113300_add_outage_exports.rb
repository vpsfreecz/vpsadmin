class AddOutageExports < ActiveRecord::Migration
  class Outage < ActiveRecord::Base ; end
  class OutageVps < ActiveRecord::Base ; end

  def change
    create_table :outage_users do |t|
      t.references  :outage,         null: false
      t.references  :user,           null: false
      t.integer     :vps_count,      null: false, default: 0
      t.integer     :export_count,   null: false, default: 0
    end

    add_index :outage_users, %i(outage_id user_id), unique: true
    add_index :outage_users, :outage_id
    add_index :outage_users, :user_id

    reversible do |dir|
      dir.up do
        Outage.all.each do |outage|
          OutageVps.select('outage_vpses.*, COUNT(*) AS vps_count').where(
            outage_id: outage.id,
          ).group('user_id').each do |outage_vps|
            OutageUser.create!(
              outage_id: outage.id,
              user_id: outage_vps.user_id,
              vps_count: outage_vps.vps_count,
              export_count: 0,
            )
          end
        end
      end
    end

    create_table :outage_exports do |t|
      t.references  :outage,         null: false
      t.references  :export,         null: false
      t.references  :user,           null: false
      t.references  :environment,    null: false
      t.references  :location,       null: false
      t.references  :node,           null: false
    end

    add_index :outage_exports, %i(outage_id export_id), unique: true
    add_index :outage_exports, :outage_id
    add_index :outage_exports, :export_id
    add_index :outage_exports, :user_id
    add_index :outage_exports, :environment_id
    add_index :outage_exports, :location_id
    add_index :outage_exports, :node_id
  end
end
