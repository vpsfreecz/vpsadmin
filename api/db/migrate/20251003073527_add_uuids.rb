class AddUuids < ActiveRecord::Migration[7.2]
  def change
    create_table :uuids do |t|
      t.string      :uuid,            null: false, limit: 36
      t.references  :owner,           null: true, polymorphic: true, index: true
      t.datetime    :created_at,      null: false
    end

    add_index :uuids, :uuid, unique: true
  end
end
