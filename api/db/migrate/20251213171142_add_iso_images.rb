class AddIsoImages < ActiveRecord::Migration[7.2]
  def change
    create_table :iso_images do |t|
      t.references :storage_pool,       null: false
      t.string     :name,               null: false, limit: 100
      t.string     :label,              null: false, limit: 100
      t.timestamps                      null: false
    end

    add_column :vpses, :iso_image_id, :bigint, null: true
    add_index :vpses, :iso_image_id
  end
end
