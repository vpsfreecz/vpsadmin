class AddDnsServers < ActiveRecord::Migration[7.1]
  def change
    create_table :dns_servers do |t|
      t.references  :node,                    null: false
      t.string      :name,                    null: false, limit: 255
      t.boolean     :enable_user_dns_zones,   null: false, default: false
      t.timestamps                            null: false
    end

    add_index :dns_servers, :name, unique: true

    create_table :dns_zones do |t|
      t.references  :user,                    null: true
      t.string      :name,                    null: false, limit: 500
      t.string      :reverse_network_address, null: true,  limit: 46
      t.integer     :reverse_network_prefix,  null: true
      t.string      :label,                   null: false, limit: 500, default: ''
      t.integer     :zone_role,               null: false, default: 0 # forward/reverse
      t.integer     :zone_source,             null: false, default: 0 # internal/external
      t.integer     :default_ttl,             null: true,  default: 3600
      t.string      :email,                   null: true,  limit: 255
      t.integer     :serial,                  null: true,  unsigned: true, default: 1
      t.string      :tsig_algorithm,          null: false, limit: 20, default: 'none'
      t.string      :tsig_key,                null: false, limit: 255, default: ''
      t.boolean     :enabled,                 null: false, default: true
      t.timestamps                            null: false
    end

    add_index :dns_zones, :name, unique: true
    add_index :dns_zones, :zone_source

    create_table :dns_server_zones do |t|
      t.references  :dns_server,              null: false
      t.references  :dns_zone,                null: false
      t.timestamps                            null: false
    end

    add_index :dns_server_zones, %i[dns_server_id dns_zone_id], unique: true

    create_table :dns_zone_transfers do |t|
      t.references  :dns_zone,                null: false
      t.references  :host_ip_address,         null: false
      t.integer     :peer_type,               null: false, default: 0
      t.timestamps                            null: false
    end

    add_index :dns_zone_transfers, %i[dns_zone_id host_ip_address_id], unique: true

    create_table :dns_records do |t|
      t.references  :dns_zone,                null: false
      t.string      :name,                    null: false, limit: 255
      t.string      :record_type,             null: false, limit: 10
      t.text        :content,                 null: false, limit: 64_000
      t.integer     :ttl,                     null: true
      t.integer     :priority,                null: true
      t.boolean     :enabled,                 null: false, default: true
      t.references  :host_ip_address,         null: true,  index: false
      t.timestamps                            null: false
    end

    add_index :dns_records, :host_ip_address_id, unique: true

    create_table :dns_record_logs do |t|
      t.references  :dns_zone,                null: false
      t.integer     :change_type,             null: false
      t.string      :name,                    null: false, limit: 255
      t.string      :record_type,             null: false, limit: 10
      t.text        :content,                 null: false, limit: 64_000
      t.timestamps                            null: false
    end

    add_column :ip_addresses, :reverse_dns_zone_id, :bigint, null: true
    add_index :ip_addresses, :reverse_dns_zone_id

    add_column :host_ip_addresses, :reverse_dns_record_id, :bigint, null: true
    add_index :host_ip_addresses, :reverse_dns_record_id, unique: true
  end
end
