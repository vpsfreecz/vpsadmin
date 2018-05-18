class MakeIpAddressSizeDecimal < ActiveRecord::Migration
  def up
    change_column :ip_addresses, :size, :decimal, precision: 40, scale: 0, null: false
  end

  def down
    change_column :ip_addresses, :size, 'bigint unsigned ', null: false
  end
end
