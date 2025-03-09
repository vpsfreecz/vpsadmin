class AddVpsUserData < ActiveRecord::Migration[7.2]
  def change
    add_column :os_templates, :cloud_init, :boolean, null: false, default: false

    create_table :vps_user_data do |t|
      t.references  :user,               null: false
      t.string      :label,              null: false, limit: 255
      t.integer     :format,             null: false, default: 0
      t.text        :content,            null: false
      t.timestamps
    end

    add_index :vps_user_data, :format
  end
end
