class AddVpsBgp < ActiveRecord::Migration[7.2]
  class VpsBgpAsn < ActiveRecord::Base; end

  def change
    create_table :vps_bgp_peers do |t|
      t.references  :vps,                        null: false, unique: true
      t.references  :host_ip_address,            null: false
      t.integer     :protocol,                   null: false
      t.integer     :route_limit,                null: false, default: 256
      t.boolean     :enabled,                    null: false, default: true
      t.integer     :confirmed,                  null: false, default: 0
      t.timestamps                               null: false
    end

    add_index :vps_bgp_peers, :protocol
    add_index :vps_bgp_peers, :confirmed

    create_table :vps_bgp_ip_addresses do |t|
      t.references  :vps_bgp_peer,               null: false
      t.references  :ip_address,                 null: false
      t.integer     :priority,                   null: false, default: 0
      t.integer     :confirmed,                  null: false, default: 0
      t.timestamps                               null: false
    end

    add_index :vps_bgp_ip_addresses, %i[vps_bgp_peer_id ip_address_id], unique: true
    add_index :vps_bgp_ip_addresses, :priority
    add_index :vps_bgp_ip_addresses, :confirmed

    create_table :vps_bgp_asns do |t|
      t.integer     :node_asn,                   null: false, unsigned: true
      t.integer     :vps_asn,                    null: false, unsigned: true
      t.references  :vps,                        null: true,  unique: true
      t.timestamps                               null: false
    end

    add_index :vps_bgp_asns, :node_asn
    add_index :vps_bgp_asns, :vps_asn, unique: true
    add_index :vps_bgp_asns, %i[node_asn vps_asn]
    add_index :vps_bgp_asns, %i[node_asn vps_id]

    reversible do |dir|
      dir.up do
        asn = 4_290_000_000

        10_000.times do
          ::VpsBgpAsn.create!(
            node_asn: asn,
            vps_asn: asn + 1
          )

          asn += 2
        end
      end
    end
  end
end
