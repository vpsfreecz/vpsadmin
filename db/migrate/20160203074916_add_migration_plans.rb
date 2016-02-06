class AddMigrationPlans < ActiveRecord::Migration
  def change
    create_table :migration_plans do |t|
      t.integer     :state,             null: false, default: 0
      t.boolean     :stop_on_error,     null: false, default: true
      t.boolean     :send_mail,         null: false, default: true
      t.references  :user,              null: true
      t.references  :node,              null: true
      t.integer     :concurrency,       null: false
      t.string      :reason,            null: true
      t.datetime    :created_at,        null: true
      t.datetime    :finished_at,       null: true
    end

    create_table :vps_migrations do |t|
      t.references  :vps,               null: false
      t.references  :migration_plan,    null: false
      t.integer     :state,             null: false, default: 0
      t.boolean     :outage_window,     null: false, default: true
      t.references  :transaction_chain, null: true
      t.references  :src_node,          null: false
      t.references  :dst_node,          null: false
      t.datetime    :created_at,        null: true
      t.datetime    :started_at,        null: true
      t.datetime    :finished_at,       null: true
    end
  end
end
