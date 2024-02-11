class RemovePerIpShapers < ActiveRecord::Migration[6.1]
  def change
    remove_column :ip_addresses, :max_tx, :bigint, unsigned: true, null: false, default: 39_321_600
    remove_column :ip_addresses, :max_rx, :bigint, unsigned: true, null: false, default: 39_321_600
    remove_column :ip_addresses, :class_id, :integer, null: false
  end
end
