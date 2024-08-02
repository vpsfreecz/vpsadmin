class AddDnsZoneDnssec < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_zones, :dnssec_enabled, :boolean, null: false, default: false

    create_table :dnssec_records do |t|
      t.belongs_to        :dns_zone,           null: false
      t.integer           :keyid,              null: false
      t.integer           :dnskey_algorithm,   null: false
      t.string            :dnskey_pubkey,      null: false, limit: 1000
      t.integer           :ds_algorithm,       null: false
      t.integer           :ds_digest_type,     null: false
      t.string            :ds_digest,          null: false, limit: 1000
      t.timestamps
    end
  end
end
