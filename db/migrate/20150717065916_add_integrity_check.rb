class AddIntegrityCheck < ActiveRecord::Migration
  def change
    create_table :integrity_checks do |t|
      t.references  :user,               null: true
      t.integer     :status,             null: false, default: 0
      t.integer     :checked_objects,    null: false, default: 0
      t.integer     :integral_objects,   null: false, default: 0
      t.integer     :broken_objects,     null: false, default: 0
      t.integer     :checked_facts,      null: false, default: 0
      t.integer     :true_facts,         null: false, default: 0
      t.integer     :false_facts,        null: false, default: 0
      t.timestamps
      t.datetime    :finished_at,        null: true
    end

    create_table :integrity_objects do |t|
      t.references  :integrity_check,    null: false
      t.references  :node,               null: false
      t.string      :class_name,         null: false, limit: 100
      t.integer     :row_id,             null: true
      t.string      :ancestry,           null: true,  limit: 255
      t.integer     :ancestry_depth,     null: false, default: 0
      t.integer     :status,             null: false, default: 0
      t.integer     :checked_facts,      null: false, default: 0
      t.integer     :true_facts,         null: false, default: 0
      t.integer     :false_facts,        null: false, default: 0
      t.timestamps
    end

    create_table :integrity_facts do |t|
      t.references  :integrity_object,   null: false
      t.string      :name,               null: false, limit: 30
      t.string      :expected_value,     null: false, limit: 255
      t.string      :actual_value,       null: false, limit: 255
      t.integer     :status,             null: false, default: 0
      t.integer     :severity,           null: false, default: 1
      t.string      :message,            null: true,  limit: 1000
      t.datetime    :created_at
    end

    reversible do |dir|
      dir.up do
        # longtext
        change_column :transactions, :t_param, :text, :limit => 4294967295
      end

      dir.down do
        # text
        change_column :transactions, :t_param, :text, :limit => 65535
      end
    end
  end
end
