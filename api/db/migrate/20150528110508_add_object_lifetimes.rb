class AddObjectLifetimes < ActiveRecord::Migration
  def change
    create_table :object_states do |t|
      t.string      :class_name,      null: false
      t.integer     :row_id,          null: false
      t.integer     :state,           null: false
      t.references  :user,            null: true
      t.string      :reason,          null: true
      t.datetime    :expiration_date, null: true
      t.timestamps
    end
  end
end
