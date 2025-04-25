class AddDnsRecordsUserId < ActiveRecord::Migration[7.2]
  def change
    add_column :dns_records, :user_id, :integer, null: true
    add_index :dns_records, :user_id

    add_column :dns_records, :original_enabled, :boolean, null: false, default: true
  end
end
