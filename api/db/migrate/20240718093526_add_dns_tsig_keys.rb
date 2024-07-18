class AddDnsTsigKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :dns_tsig_keys do |t|
      t.references  :user,                     null: true
      t.string      :name,                     null: false, limit: 255
      t.string      :algorithm,                null: false, limit: 20
      t.string      :secret,                   null: false, limit: 255
      t.timestamps                             null: false
    end

    add_index :dns_tsig_keys, :name, unique: true

    add_column :dns_zone_transfers, :dns_tsig_key_id, :bigint, null: true
    add_index :dns_zone_transfers, :dns_tsig_key_id

    remove_column :dns_zones, :tsig_algorithm, :string, null: false, limit: 20, default: 'none'
    remove_column :dns_zones, :tsig_key, :string, null: false, limit: 255, default: ''
  end
end
