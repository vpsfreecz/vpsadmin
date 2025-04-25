class AddDnsZonesOriginalEnabled < ActiveRecord::Migration[7.2]
  def change
    add_column :dns_zones, :original_enabled, :boolean, null: false, default: true
  end
end
