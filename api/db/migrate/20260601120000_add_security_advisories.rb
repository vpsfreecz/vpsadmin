class AddSecurityAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :security_advisories do |t|
      t.integer :state, null: false, default: 0
      t.string :name, null: true, limit: 255
      t.integer :created_by_id, null: true
      t.integer :published_by_id, null: true
      t.datetime :published_at, null: true
      t.datetime :retracted_at, null: true
      t.timestamps null: false
    end

    add_index :security_advisories, :state
    add_index :security_advisories, :published_at
    add_index :security_advisories, :created_by_id
    add_index :security_advisories, :published_by_id

    create_table :security_advisory_cves do |t|
      t.references :security_advisory, null: false, index: false
      t.string :cve_id, null: false, limit: 32
    end

    add_index :security_advisory_cves,
              %i[security_advisory_id cve_id],
              unique: true,
              name: 'index_security_advisory_cves_unique'
    add_index :security_advisory_cves, :cve_id

    create_table :security_advisory_translations do |t|
      t.references :security_advisory, null: true, index: false
      t.references :security_advisory_update, null: true, index: false
      t.references :language, null: false, index: false
      t.string :summary, null: true, limit: 255
      t.text :description, null: true
      t.text :response, null: true
      t.text :message, null: true
    end

    add_index :security_advisory_translations,
              %i[security_advisory_id language_id],
              unique: true,
              name: 'index_sat_on_advisory_language'
    add_index :security_advisory_translations,
              %i[security_advisory_update_id language_id],
              unique: true,
              name: 'index_sat_on_update_language'
    add_index :security_advisory_translations, :language_id

    create_table :security_advisory_node_statuses do |t|
      t.references :security_advisory, null: false, index: false
      t.references :node, null: false, index: false
      t.integer :state, null: false, default: 0
      t.datetime :vulnerable_until, null: true
      t.datetime :mitigated_since, null: true
      t.text :note, null: true
    end

    add_index :security_advisory_node_statuses,
              %i[security_advisory_id node_id],
              unique: true,
              name: 'index_sans_on_advisory_node'
    add_index :security_advisory_node_statuses, :node_id
    add_index :security_advisory_node_statuses, :state

    create_table :security_advisory_vpses do |t|
      t.references :security_advisory, null: false, index: false
      t.references :vps, null: false, index: false
      t.references :user, null: false, index: false
      t.references :environment, null: false, index: false
      t.references :location, null: false, index: false
      t.references :node, null: false, index: false
      t.integer :node_state, null: false
      t.datetime :vulnerable_until, null: true
      t.datetime :mitigated_since, null: true
    end

    add_index :security_advisory_vpses,
              %i[security_advisory_id vps_id],
              unique: true,
              name: 'index_sav_on_advisory_vps'
    add_index :security_advisory_vpses, :user_id
    add_index :security_advisory_vpses, :environment_id
    add_index :security_advisory_vpses, :location_id
    add_index :security_advisory_vpses, :node_id

    create_table :security_advisory_users do |t|
      t.references :security_advisory, null: false, index: false
      t.references :user, null: false, index: false
      t.integer :vps_count, null: false, default: 0
    end

    add_index :security_advisory_users,
              %i[security_advisory_id user_id],
              unique: true,
              name: 'index_sau_on_advisory_user'
    add_index :security_advisory_users, :user_id

    create_table :security_advisory_updates do |t|
      t.references :security_advisory, null: false, index: false
      t.references :reported_by, null: true, index: false
      t.string :reporter_name, null: true, limit: 100
      t.integer :state, null: true
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
    end

    add_index :security_advisory_updates, :security_advisory_id
    add_index :security_advisory_updates, :reported_by_id
    add_index :security_advisory_updates, :state
  end
end
