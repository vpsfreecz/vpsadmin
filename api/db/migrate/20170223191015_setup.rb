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
      t.references  :user,           null: false
      t.string      :note,           null: true
    end

    add_index :outage_handlers, :outage_id
    add_index :outage_handlers, :user_id
    add_index :outage_handlers, %i(outage_id user_id), unique: true

    create_table :outage_reports do |t|
      t.references  :outage,         null: false
      t.references  :reported_by,    null: true
      t.datetime    :begins_at,      null: true
      t.datetime    :finished_at,    null: true
      t.integer     :duration,       null: true
      t.integer     :state,          null: true
      t.integer     :outage_type,    null: true
      t.datetime    :created_at,     null: false
      t.datetime    :updated_at,     null: true
    end
    
    add_index :outage_reports, :outage_id
    add_index :outage_reports, :reported_by_id
    add_index :outage_reports, :state
    add_index :outage_reports, :outage_type
    
    create_table :outage_translations do |t|
      t.references  :outage,         null: true
      t.references  :outage_report,  null: true
      t.references  :language,       null: false
      t.string      :summary,        null: false
      t.text        :description,    null: true
    end

    add_index :outage_translations, :outage_id
    add_index :outage_translations, :outage_report_id
    add_index :outage_translations, :language_id
    add_index :outage_translations, %i(outage_id language_id), unique: true
    add_index :outage_translations, %i(outage_report_id language_id), unique: true
  end
end
