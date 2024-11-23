class AddOsTemplatesManageHostnameDnsResolver < ActiveRecord::Migration[7.2]
  def change
    add_column :os_templates, :manage_hostname, :boolean, null: false, default: true
    add_column :os_templates, :manage_dns_resolver, :boolean, null: false, default: true
  end
end
