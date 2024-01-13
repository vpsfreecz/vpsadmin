class AddOomPreventions < ActiveRecord::Migration[7.0]
  def change
    create_table :oom_preventions do |t|
      t.references  :vps,                     null: false
      t.integer     :action,                  null: false
      t.timestamps                            null: false
    end

    add_index :oom_preventions, :action
  end
end
