class Setup < ActiveRecord::Migration
  def change
    create_table :outages do |t|
      t.boolean     :planned,        null: false
      t.datetime    :begins_at,      null: true
      t.datetime    :finished_at,    null: true
      t.integer     :duration,       null: true
      t.integer     :state,          null: false, default: 0
      t.integer     :outage_type,    null: false
      t.datetime    :created_at,     null: false
      t.datetime    :updated_at,     null: true
    end

    add_index :outages, :state
    add_index :outages, :outage_type
    add_index :outages, :planned

    create_table :outage_entities do |t|
      t.references  :outage,         null: false
      t.string      :name,           null: false, limit: 255
      t.integer     :row_id,         null: true
    end

    add_index :outage_entities, :outage_id
    add_index :outage_entities, :name
    add_index :outage_entities, :row_id
    add_index :outage_entities, %i(outage_id name row_id), unique: true

    create_table :outage_handlers do |t|
      t.references  :outage,         null: false
      t.references  :user,           null: true
      t.string      :full_name,      null: false, limit: 100
      t.string      :note,           null: true
    end

    add_index :outage_handlers, :outage_id
    add_index :outage_handlers, :user_id
    add_index :outage_handlers, %i(outage_id user_id), unique: true

    create_table :outage_updates do |t|
      t.references  :outage,         null: false
      t.references  :reported_by,    null: true
      t.string      :reporter_name,  null: true
      t.datetime    :begins_at,      null: true
      t.datetime    :finished_at,    null: true
      t.integer     :duration,       null: true
      t.integer     :state,          null: true
      t.integer     :outage_type,    null: true
      t.datetime    :created_at,     null: false
      t.datetime    :updated_at,     null: true
    end

    add_index :outage_updates, :outage_id
    add_index :outage_updates, :reported_by_id
    add_index :outage_updates, :state
    add_index :outage_updates, :outage_type

    create_table :outage_translations do |t|
      t.references  :outage,         null: true
      t.references  :outage_update,  null: true
      t.references  :language,       null: false
      t.string      :summary,        null: true
      t.text        :description,    null: true
    end

    add_index :outage_translations, :outage_id
    add_index :outage_translations, :outage_update_id
    add_index :outage_translations, :language_id
    add_index :outage_translations, %i(outage_id language_id), unique: true
    add_index :outage_translations, %i(outage_update_id language_id), unique: true

    create_table :outage_vpses do |t|
      t.references  :outage,         null: false
      t.references  :vps,            null: false
      t.references  :user,           null: false
      t.references  :environment,    null: false
      t.references  :location,       null: false
      t.references  :node,           null: false
      t.boolean     :direct,         null: false
    end

    add_index :outage_vpses, %i(outage_id vps_id), unique: true
    add_index :outage_vpses, :outage_id
    add_index :outage_vpses, :vps_id
    add_index :outage_vpses, :user_id
    add_index :outage_vpses, :environment_id
    add_index :outage_vpses, :location_id
    add_index :outage_vpses, :node_id

    create_table :outage_vps_mounts do |t|
      t.references  :outage_vps,     null: false
      t.references  :mount,          null: false
      t.references  :src_node,       null: false
      t.references  :src_pool,       null: false
      t.references  :src_dataset,    null: false
      t.references  :src_snapshot,   null: true
      t.string      :dataset_name,   null: false, limit: 500
      t.string      :snapshot_name,  null: true,  limit: 255
      t.string      :mountpoint,     null: false, limit: 500
    end

    add_index :outage_vps_mounts, %i(outage_vps_id mount_id), unique: true
    add_index :outage_vps_mounts, :outage_vps_id
    add_index :outage_vps_mounts, :mount_id
  end
end
