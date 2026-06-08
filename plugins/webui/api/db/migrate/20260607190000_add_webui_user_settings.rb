class AddWebuiUserSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :webui_user_settings do |t|
      t.references :user, null: false, index: false
      t.string :namespace, null: false, limit: 75
      t.string :key, null: false, limit: 100
      t.text :value, null: false
      t.timestamps null: false
    end

    add_index :webui_user_settings,
              %i[user_id namespace key],
              unique: true,
              name: 'index_webui_user_settings_unique_key'
    add_index :webui_user_settings,
              %i[user_id namespace],
              name: 'index_webui_user_settings_on_user_namespace'
  end
end
