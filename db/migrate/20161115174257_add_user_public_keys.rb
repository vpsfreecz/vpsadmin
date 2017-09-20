class AddUserPublicKeys < ActiveRecord::Migration
  def change
    create_table :user_public_keys do |t|
      t.references  :user,               null: false
      t.string      :label,              null: false, limit: 255
      t.text        :key,                null: false, limit: 5000
      t.boolean     :auto_add,           null: false, default: false
      t.string      :fingerprint,        null: false, limit: 50
      t.string      :comment,            null: false, limit: 255
      t.timestamps
    end

    add_index :user_public_keys, :user_id
  end
end
