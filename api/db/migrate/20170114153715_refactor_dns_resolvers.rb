class RefactorDnsResolvers < ActiveRecord::Migration
  def change
    rename_table :cfg_dns, :dns_resolvers
    rename_column :dns_resolvers, :dns_id, :id
    rename_column :dns_resolvers, :dns_ip, :addrs
    rename_column :dns_resolvers, :dns_label, :label
    rename_column :dns_resolvers, :dns_is_universal, :is_universal
    rename_column :dns_resolvers, :dns_location, :location_id
  end
end
