class AddDatasetInPoolExpansions < ActiveRecord::Migration[7.0]
  def change
    create_table :dataset_expansions do |t|
      t.references  :dataset,                      null: false
      t.integer     :state,                        null: false, default: 0
      t.integer     :original_refquota,            null: false
      t.integer     :added_space,                  null: false
      t.boolean     :enable_notifications,         null: false, default: true
      t.boolean     :stop_vps,                     null: false, default: true
      t.datetime    :deadline,                     null: true
      t.datetime    :last_shrink,                  null: true
      t.datetime    :last_vps_stop,                null: true
      t.timestamps                                 null: false
    end

    create_table :dataset_expansion_histories do |t|
      t.references  :dataset_expansion,            null: false
      t.integer     :original_refquota,            null: false
      t.integer     :new_refquota,                 null: false
      t.integer     :added_space,                  null: false
      t.references  :admin,                        null: true
      t.timestamps                                 null: false
    end

    create_table :dataset_expansion_events do |t|
      t.references  :dataset,                      null: false
      t.integer     :original_refquota,            null: false
      t.integer     :new_refquota,                 null: false
      t.integer     :added_space,                  null: false
      t.timestamps                                 null: false
    end

    add_column :datasets, :dataset_expansion_id, :integer, null: true
    add_index :datasets, :dataset_expansion_id, unique: true
  end
end
