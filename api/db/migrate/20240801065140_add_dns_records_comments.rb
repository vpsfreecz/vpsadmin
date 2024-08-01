class AddDnsRecordsComments < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_records, :comment, :string, limit: 255, null: false, default: ''
  end
end
