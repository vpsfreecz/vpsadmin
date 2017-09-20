class AddDnsResolverIpVersion < ActiveRecord::Migration
  def change
    add_column :cfg_dns, :ip_version, :integer, null: true, default: 4
  end
end
