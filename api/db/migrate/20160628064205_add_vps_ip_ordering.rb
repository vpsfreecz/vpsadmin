class AddVpsIpOrdering < ActiveRecord::Migration
  def change
    add_column :vps_ip, :order, :integer, null: true
  end
end
