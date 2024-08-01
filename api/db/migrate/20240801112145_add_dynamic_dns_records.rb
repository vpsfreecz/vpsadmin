class AddDynamicDnsRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_records, :update_token_id, :bigint, null: true
    add_index :dns_records, :update_token_id
  end
end
