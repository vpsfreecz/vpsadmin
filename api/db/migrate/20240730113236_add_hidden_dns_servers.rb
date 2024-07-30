class AddHiddenDnsServers < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_servers, :hidden, :boolean, null: false, default: false
  end
end
