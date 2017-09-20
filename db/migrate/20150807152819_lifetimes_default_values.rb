class LifetimesDefaultValues < ActiveRecord::Migration
  def change
    create_table :default_lifetime_values do |t|
      t.references  :environment,             null: true
      t.string      :class_name,              null: false, limit: 50
      t.integer     :direction,               null: false
      t.integer     :state,                   null: false
      t.integer     :add_expiration,          null: true
      t.string      :reason,                  null: false
    end
  end
end
